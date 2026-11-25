package probe;

/**
	A returned omitted input takes the result that its peer returns choose (haxe_ocaml-catyk).
	`M14ReturnedInputBindingTest` records upstream's signatures for this class.
**/
class Returns {
	public static function nullFallback(first, second) {
		if (second == null)
			return first;
		return second;
	}

	public static function inputThenInt(first, flag:Bool) {
		if (flag)
			return first;
		return 5;
	}

	public static function intThenInput(first, flag:Bool) {
		if (flag)
			return 5;
		return first;
	}

	public static function inputThenNullInt(first, flag:Bool, other:Null<Int>) {
		if (flag)
			return first;
		return other;
	}

	public static function inputThenDynamic(first, flag:Bool, other:Dynamic) {
		if (flag)
			return first;
		return other;
	}
}
