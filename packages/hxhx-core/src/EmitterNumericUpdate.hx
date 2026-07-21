/**
	Chooses the native arithmetic used for a mutable numeric local update.

	Stage3 represents ordinary Haxe `Int` values with the OCaml `int` helpers and
	`haxe.Int64` values with the repo-owned Int64 helper module. Keeping these
	target spellings outside `EmitterStage` prevents a small representation choice
	from renumbering thousands of generated temporaries in that large module.
**/
class EmitterNumericUpdate {
	/**
		Recognize the two source spellings used to seed an unannotated Int64 local.

		The parser stores `haxe.Int64` as nested field access (`haxe` then `Int64`),
		not as one identifier containing a dot. This is a bounded bootstrap bridge for
		the existing initializer-based local-hint pass. It deliberately does not make
		all expression typing recognize an Int64 merely from its source spelling;
		declaration-scoped semantic local types are tracked by haxe_ocaml-i7d5a.
	**/
	public static function isStandardInt64Provider(owner:HxExpr):Bool {
		return switch (owner) {
			case EIdent("Int64") | EField(EIdent("haxe"), "Int64"): true;
			case _: false;
		};
	}

	/** Return the add/sub helper for the selected numeric representation. */
	public static function operation(isInt64:Bool, increment:Bool):String {
		if (isInt64)
			return increment ? "Haxe_Int64.add" : "Haxe_Int64.sub";
		return increment ? "HxInt.add" : "HxInt.sub";
	}

	/** Return the value one in the selected numeric representation. */
	public static function one(isInt64:Bool):String {
		return isInt64 ? "(Haxe_Int64.ofInt (1))" : "1";
	}
}
