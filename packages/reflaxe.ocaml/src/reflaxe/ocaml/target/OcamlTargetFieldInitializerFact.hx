package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Static field roles admitted by the first shared-target program contract. **/
enum OcamlTargetFieldInitializerRole {
	StaticField;
}

/** Host-neutral source identity for one initialized field. **/
typedef OcamlTargetFieldInitializerSignature = {
	final moduleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final role:OcamlTargetFieldInitializerRole;
	final semanticTypeDisplay:String;
}

/**
	One immutable field initializer copied from either compiler host.

	Revision 1 accepts only static `Int`, `Bool`, or `String` fields whose
	initializer has the exact same semantic type. Mutability and visibility remain
	declaration facts; the whole-program target core validates them before output.
**/
class OcamlTargetFieldInitializerFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-target-field-initializer-v1";

	public final moduleId:String;
	public final sourceTypeName:String;
	public final sourceFieldName:String;
	public final role:OcamlTargetFieldInitializerRole;
	public final semanticTypeDisplay:String;
	public final initializer:OcamlTargetExpressionFact;

	final targetIdentity:String;
	final canonicalIdentity:String;

	public function new(signature:OcamlTargetFieldInitializerSignature, initializer:OcamlTargetExpressionFact) {
		if (signature == null)
			throw "OCaml target field initializer requires a source signature";
		moduleId = required(signature.moduleId, "module ID");
		sourceTypeName = required(signature.sourceTypeName, "source type name");
		sourceFieldName = required(signature.sourceFieldName, "source field name");
		if (signature.role == null)
			throw "OCaml target field initializer requires a role";
		role = signature.role;
		semanticTypeDisplay = required(signature.semanticTypeDisplay, "semantic type");
		if (initializer == null)
			throw "OCaml target field initializer requires a normalized expression";
		this.initializer = initializer;
		validateRevisionOne(role, semanticTypeDisplay, this.initializer);
		targetIdentity = identityFor(signature);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode([SCHEMA_REVISION, targetIdentity, initializer.getCanonicalIdentity()]));
	}

	public static function identityFor(signature:OcamlTargetFieldInitializerSignature):String {
		if (signature == null)
			throw "OCaml target field initializer identity requires a source signature";
		return "field-initializer:" + Sha256.encode(OcamlTargetDeclarationCodec.encode([
			SCHEMA_REVISION,
			required(signature.moduleId, "module ID"),
			required(signature.sourceTypeName, "source type name"),
			required(signature.sourceFieldName, "source field name"),
			roleName(signature.role),
			required(signature.semanticTypeDisplay, "semantic type")
		]));
	}

	public function getTargetIdentity():String
		return targetIdentity;

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Returns the protocol spelling without target-specific enum stringification. **/
	static function roleName(role:OcamlTargetFieldInitializerRole):String {
		return switch (role) {
			case StaticField: "StaticField";
		};
	}

	static function validateRevisionOne(role:OcamlTargetFieldInitializerRole, semanticTypeDisplay:String, initializer:OcamlTargetExpressionFact):Void {
		final exactType = semanticTypeDisplay == "Int" || semanticTypeDisplay == "Bool" || semanticTypeDisplay == "String";
		if (role != StaticField || !exactType || initializer.semanticTypeDisplay != semanticTypeDisplay)
			throw "OCaml target field initializer revision 1 requires a static exact Int, Bool, or String initializer";
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target field initializer requires " + label;
		return normalized;
	}
}
