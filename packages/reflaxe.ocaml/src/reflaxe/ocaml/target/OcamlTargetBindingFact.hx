package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Source declaration roles that affect lexical binding identity. **/
enum OcamlTargetBindingRole {
	Parameter;
	Variable;
	LoopVariable;
	CatchVariable;
	PatternVariable;
	LambdaParameter;
	ComprehensionVariable;
}

/**
	One host-neutral source binding used by declarations and local reads.

	The target identity does not contain a macro `TVar.id`, native `TyLocalId`,
	rendered target name, or compiler-created temporary. Temporary identities need
	a separate pass-owned contract before they can enter recursive target input.
**/
class OcamlTargetBindingFact {
	public static final SCHEMA_REVISION = "reflaxe-ocaml-target-binding-v1";

	public final ownerIdentity:String;
	public final declarationPath:String;
	public final role:OcamlTargetBindingRole;
	public final sourceName:String;
	public final semanticTypeDisplay:String;

	final canonicalIdentity:String;

	public function new(ownerIdentity:String, declarationPath:String, role:OcamlTargetBindingRole, sourceName:String, semanticTypeDisplay:String) {
		this.ownerIdentity = required(ownerIdentity, "owner identity");
		this.declarationPath = OcamlTargetExpressionPath.require(declarationPath);
		if (role == null)
			throw "OCaml target binding requires a declaration role";
		this.role = role;
		this.sourceName = required(sourceName, "source name");
		this.semanticTypeDisplay = required(semanticTypeDisplay, "semantic type");
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode([
			SCHEMA_REVISION,
			this.ownerIdentity,
			this.declarationPath,
			roleName(role),
			this.sourceName,
			this.semanticTypeDisplay
		]));
	}

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Returns the protocol spelling without target-specific enum stringification. **/
	static function roleName(role:OcamlTargetBindingRole):String {
		return switch (role) {
			case Parameter: "Parameter";
			case Variable: "Variable";
			case LoopVariable: "LoopVariable";
			case CatchVariable: "CatchVariable";
			case PatternVariable: "PatternVariable";
			case LambdaParameter: "LambdaParameter";
			case ComprehensionVariable: "ComprehensionVariable";
		};
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target binding requires " + label;
		return normalized;
	}
}
