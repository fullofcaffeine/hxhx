package probe;

typedef Pair = {a:Int, b:String};

/**
	An object literal assigned to an untyped local shares its field values' inference variables
	(haxe_ocaml-rten2.6). `M14LiteralTermInferenceTest` records upstream's signatures for this class.
**/
class LiteralTerm {
	public static function structured(?p):Pair {
		var e = null;
		e = {a: 1, b: p};
		return e;
	}

	public static function nested(?p):{inner:Pair} {
		var e = null;
		e = {inner: {a: 1, b: p}};
		return e;
	}

	public static function withNull(?p):{a:Null<Int>, b:String} {
		var e = null;
		e = {a: null, b: p};
		return e;
	}

	public static function uninitialized(?p):Pair {
		var e;
		e = {a: 2, b: p};
		return e;
	}

	public static function closed():Pair {
		var e = null;
		e = {a: 3, b: "c"};
		return e;
	}
}
