import TyLocalDeclarationKind.TyLocalDeclarationKindTools;

/**
	Deterministic identity for one declaration inside a typed function revision.

	Source declarations use their source-order ordinal and declaration kind.
	Compiler-generated declarations use their versioned pass and pass-local
	ordinal. Both forms include the owning function. Names remain
	diagnostic/source-projection facts; they do not decide whether two
	declarations are the same local.
**/
class TyLocalId {
	final canonicalKey:String;

	function new(canonicalKey:String) {
		if (canonicalKey == null || canonicalKey.length == 0)
			throw "local declaration identity requires a canonical key";
		this.canonicalKey = canonicalKey;
	}

	/** Identify one source declaration without depending on target or traversal allocation. **/
	public static function forSourceDeclaration(functionIdentity:String, declarationOrdinal:Int, kind:TyLocalDeclarationKind, sourceName:String):TyLocalId {
		final owner = functionIdentity == null ? "" : functionIdentity;
		final name = sourceName == null ? "" : sourceName;
		if (owner.length == 0)
			throw "local declaration identity requires a function owner";
		if (declarationOrdinal < 0)
			throw "local declaration identity requires a non-negative ordinal";
		return new TyLocalId(owner
			+ "#local:"
			+ declarationOrdinal
			+ ":"
			+ TyLocalDeclarationKindTools.canonicalName(kind)
			+ ":"
			+ name.length
			+ ":"
			+ name);
	}

	/**
		Identify one local introduced by a deterministic shared lowering pass.

		The pass identity is part of the key so two independent transforms may use
		the same ordinal and diagnostic name without claiming the same declaration.
	**/
	public static function forCompilerTemporary(functionIdentity:String, passIdentity:String, declarationOrdinal:Int, generatedName:String):TyLocalId {
		final owner = functionIdentity == null ? "" : functionIdentity;
		final pass = passIdentity == null ? "" : passIdentity;
		final name = generatedName == null ? "" : generatedName;
		if (owner.length == 0)
			throw "compiler temporary identity requires a function owner";
		if (pass.length == 0)
			throw "compiler temporary identity requires a lowering pass";
		if (declarationOrdinal < 0)
			throw "compiler temporary identity requires a non-negative ordinal";
		return new TyLocalId(owner + "#temporary:" + pass.length + ":" + pass + ":" + declarationOrdinal + ":" + name.length + ":" + name);
	}

	public function getCanonicalKey():String
		return canonicalKey;

	public function equals(other:TyLocalId):Bool
		return other != null && canonicalKey == other.getCanonicalKey();

	public function toString():String
		return canonicalKey;
}
