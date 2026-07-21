/**
	Chooses the native arithmetic used for a mutable numeric local update.

	Stage3 represents ordinary Haxe `Int` values with the OCaml `int` helpers and
	`haxe.Int64` values with the repo-owned Int64 helper module. Keeping these
	target spellings outside `EmitterStage` prevents a small representation choice
	from renumbering thousands of generated temporaries in that large module.
**/
class EmitterNumericUpdate {
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
