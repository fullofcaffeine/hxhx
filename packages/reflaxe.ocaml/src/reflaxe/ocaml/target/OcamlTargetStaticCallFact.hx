package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Exact source declaration and value types selected by the host for a static call. **/
typedef OcamlTargetStaticCallReference = {
	final moduleId:String;
	final sourceTypeName:String;
	final sourceFunctionName:String;
	final argumentTypeDisplays:Array<String>;
	final returnTypeDisplay:String;
}

/**
	An immutable direct call with exact primitive arguments and a primitive or Void result.

	Hosts must copy a resolved ordinary method declaration. The enclosing function
	checks the source owner, and the program checks that the target declaration has
	an admitted body. OCaml names are selected later by the shared target lowerer.
**/
class OcamlTargetStaticCallFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-static-call-v2";

	public final moduleId:String;
	public final sourceTypeName:String;
	public final sourceFunctionName:String;
	public final returnTypeDisplay:String;

	final argumentTypeDisplays:Array<String>;

	final canonicalIdentity:String;

	public function new(reference:OcamlTargetStaticCallReference) {
		if (reference == null)
			throw "OCaml static call requires a resolved declaration reference";
		moduleId = required(reference.moduleId);
		sourceTypeName = required(reference.sourceTypeName);
		sourceFunctionName = required(reference.sourceFunctionName);
		if (reference.argumentTypeDisplays == null)
			throw "OCaml static call requires argument types";
		argumentTypeDisplays = reference.argumentTypeDisplays.copy();
		returnTypeDisplay = reference.returnTypeDisplay;
		if (!OcamlTargetFunctionFact.admitsResult(returnTypeDisplay))
			throw "OCaml static call has unsupported result type";
		final parts:Array<Null<String>> = [
			SCHEMA_REVISION,
			moduleId,
			sourceTypeName,
			sourceFunctionName,
			returnTypeDisplay,
			Std.string(argumentTypeDisplays.length)
		];
		for (type in argumentTypeDisplays) {
			if (!OcamlTargetFunctionFact.admitsValue(type))
				throw "OCaml static call has unsupported argument type";
			parts.push(type);
		}
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(parts));
	}

	public function copyArgumentTypeDisplays():Array<String>
		return argumentTypeDisplays.copy();

	/** The referenced declaration must have the exact represented call signature. **/
	public function matchesFunction(fn:OcamlTargetFunctionFact):Bool {
		if (!belongsTo(fn.moduleId, fn.sourceTypeName)
			|| sourceFunctionName != fn.sourceFunctionName
			|| returnTypeDisplay != fn.returnTypeDisplay)
			return false;
		final actual = fn.copyArgumentTypeDisplays();
		if (actual.length != argumentTypeDisplays.length)
			return false;
		for (index in 0...actual.length)
			if (actual[index] != argumentTypeDisplays[index])
				return false;
		return true;
	}

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function belongsTo(moduleId:String, sourceTypeName:String):Bool
		return this.moduleId == moduleId && this.sourceTypeName == sourceTypeName;

	static function required(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml static call requires complete source declaration names";
		return normalized;
	}
}
