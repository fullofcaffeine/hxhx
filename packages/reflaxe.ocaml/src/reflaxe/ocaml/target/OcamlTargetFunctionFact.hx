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

	Revision 1 admits only static, zero-argument, `Void` functions. This is enough
	to prove the preprocessing and target-execution boundary without pretending
	that arguments, receiver state, returns, or captures already cross it.
**/
class OcamlTargetFunctionFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-target-function-v1";

	public final moduleId:String;
	public final sourceTypeName:String;
	public final sourceFunctionName:String;
	public final role:OcamlTargetFunctionRole;
	public final returnTypeDisplay:String;
	public final body:OcamlTargetExpressionFact;

	final argumentTypeDisplays:Array<String>;
	final targetIdentity:String;
	final canonicalIdentity:String;

	public function new(signature:OcamlTargetFunctionSignature, body:OcamlTargetExpressionFact) {
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
		validateRevisionOne();
		targetIdentity = identityFor(signature);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationRequest.encode([SCHEMA_REVISION, targetIdentity, body.getCanonicalIdentity()]));
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
			Std.string(signature.role),
			Std.string(arguments.length),
			required(signature.returnTypeDisplay, "return type")
		];
		for (argument in arguments)
			parts.push(required(argument, "argument type"));
		return "function:" + Sha256.encode(OcamlTargetDeclarationRequest.encode(parts));
	}

	public function copyArgumentTypeDisplays():Array<String>
		return argumentTypeDisplays.copy();

	public function getTargetIdentity():String
		return targetIdentity;

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	function validateRevisionOne():Void {
		if (role != StaticFunction || argumentTypeDisplays.length != 0 || returnTypeDisplay != "Void" || body.semanticTypeDisplay != "Void")
			throw "OCaml target function revision 1 requires a static zero-argument Void function and body";
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target function requires " + label;
		return normalized;
	}
}
