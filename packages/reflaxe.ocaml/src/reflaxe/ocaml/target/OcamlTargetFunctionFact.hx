package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Function roles admitted by the first shared-target function contract. **/
enum OcamlTargetFunctionRole {
	StaticFunction;
}

/** Named source signature copied without host compiler object identity. **/
typedef OcamlTargetFunctionSignature = {
	final moduleId:String;
	final sourceTypeName:String;
	final sourceFunctionName:String;
	final role:OcamlTargetFunctionRole;
	final argumentTypeDisplays:Array<String>;
	final returnTypeDisplay:String;
}

/**
	One immutable function copied independently from either compiler host.

	Exact primitive parameters and terminal returns cross this boundary with
	ordered binding identities. Receiver state and captures remain unsupported.
**/
class OcamlTargetFunctionFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-target-function-v2";

	public final moduleId:String;
	public final sourceTypeName:String;
	public final sourceFunctionName:String;
	public final role:OcamlTargetFunctionRole;
	public final returnTypeDisplay:String;
	public final body:OcamlTargetStatementFact;

	final parameters:Array<OcamlTargetBindingFact>;

	final argumentTypeDisplays:Array<String>;
	final targetIdentity:String;
	final canonicalIdentity:String;

	public function new(signature:OcamlTargetFunctionSignature, body:OcamlTargetStatementFact, parameters:Array<OcamlTargetBindingFact>) {
		if (signature == null)
			throw "OCaml target function requires a source signature";
		this.moduleId = required(signature.moduleId, "module ID");
		this.sourceTypeName = required(signature.sourceTypeName, "source type name");
		this.sourceFunctionName = required(signature.sourceFunctionName, "source function name");
		if (signature.role == null)
			throw "OCaml target function requires a role";
		this.role = signature.role;
		this.argumentTypeDisplays = signature.argumentTypeDisplays == null ? [] : signature.argumentTypeDisplays.copy();
		for (argumentType in this.argumentTypeDisplays)
			required(argumentType, "argument type");
		this.returnTypeDisplay = required(signature.returnTypeDisplay, "return type");
		if (body == null)
			throw "OCaml target function requires a normalized body";
		this.body = body;
		if (parameters == null || parameters.length != argumentTypeDisplays.length)
			throw "OCaml target function requires every ordered parameter binding";
		this.parameters = parameters.copy();
		targetIdentity = identityFor(signature);
		if (role != StaticFunction
			|| !admitsResult(returnTypeDisplay)
			|| body.path != OcamlTargetExpressionPath.ROOT
			|| body.kind != BlockStatement
			|| !body.admitsFunctionResult(returnTypeDisplay))
			throw "OCaml target function has unsupported signature or return control";
		final names:Map<String, Bool> = [];
		for (index in 0...parameters.length) {
			final parameter = parameters[index];
			if (parameter == null
				|| parameter.role != Parameter
				|| parameter.ownerIdentity != targetIdentity
				|| parameter.declarationPath != OcamlTargetExpressionPath.indexed(OcamlTargetExpressionPath.ROOT, "parameter", index)
				|| parameter.semanticTypeDisplay != argumentTypeDisplays[index]
				|| !admitsValue(argumentTypeDisplays[index])
				|| names.exists(parameter.sourceName))
				throw "OCaml target function has inconsistent parameter facts";
			names.set(parameter.sourceName, true);
		}
		body.validateBindings(targetIdentity, this.parameters);
		for (call in body.copyStaticCalls())
			if (!call.belongsTo(moduleId, sourceTypeName))
				throw "OCaml target function does not admit cross-owner static calls";
		final parts:Array<Null<String>> = [SCHEMA_REVISION, targetIdentity, body.getCanonicalIdentity()];
		for (parameter in this.parameters)
			parts.push(parameter.getCanonicalIdentity());
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(parts));
	}

	public static function identityFor(signature:OcamlTargetFunctionSignature):String {
		if (signature == null)
			throw "OCaml target function identity requires a source signature";
		final arguments = signature.argumentTypeDisplays == null ? [] : signature.argumentTypeDisplays;
		final parts:Array<Null<String>> = [
			SCHEMA_REVISION,
			required(signature.moduleId, "module ID"),
			required(signature.sourceTypeName, "source type name"),
			required(signature.sourceFunctionName, "source function name"),
			roleName(signature.role),
			Std.string(arguments.length),
			required(signature.returnTypeDisplay, "return type")
		];
		for (argument in arguments)
			parts.push(required(argument, "argument type"));
		return "function:" + Sha256.encode(OcamlTargetDeclarationCodec.encode(parts));
	}

	public function copyArgumentTypeDisplays():Array<String>
		return argumentTypeDisplays.copy();

	public function copyParameters():Array<OcamlTargetBindingFact>
		return parameters.copy();

	public static function admitsValue(typeDisplay:String):Bool
		return typeDisplay == "Int" || typeDisplay == "Bool" || typeDisplay == "String";

	public static function admitsResult(typeDisplay:String):Bool
		return typeDisplay == "Void" || admitsValue(typeDisplay);

	public function getTargetIdentity():String
		return targetIdentity;

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Returns the protocol spelling without target-specific enum stringification. **/
	static function roleName(role:OcamlTargetFunctionRole):String {
		return switch (role) {
			case StaticFunction: "StaticFunction";
		};
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target function requires " + label;
		return normalized;
	}
}
