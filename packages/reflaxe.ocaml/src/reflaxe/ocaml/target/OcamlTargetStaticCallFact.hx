package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Exact source declaration selected by the host for a static zero-argument Void call. **/
typedef OcamlTargetStaticCallReference = {
	final moduleId:String;
	final sourceTypeName:String;
	final sourceFunctionName:String;
}

/**
	An immutable direct call with no receiver, argument conversion, or result carrier.

	Hosts must copy a resolved ordinary method declaration. The enclosing function
	checks the source owner, and the program checks that the target declaration has
	an admitted body. OCaml names are selected later by the shared target lowerer.
**/
class OcamlTargetStaticCallFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-static-void-call-v1";

	public final moduleId:String;
	public final sourceTypeName:String;
	public final sourceFunctionName:String;

	final canonicalIdentity:String;

	public function new(reference:OcamlTargetStaticCallReference) {
		if (reference == null)
			throw "OCaml static call requires a resolved declaration reference";
		moduleId = required(reference.moduleId);
		sourceTypeName = required(reference.sourceTypeName);
		sourceFunctionName = required(reference.sourceFunctionName);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode([SCHEMA_REVISION, moduleId, sourceTypeName, sourceFunctionName]));
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
