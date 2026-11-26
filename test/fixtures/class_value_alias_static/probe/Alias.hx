package probe;

class Target {
	public static var count = 0;

	public static function somefunc()
		return 42;

	public static function twice(x:Int):Int
		return x * 2;
}

/** `M14ClassValueAliasStaticTest` records upstream's signatures for these methods. */
class Alias {
	public static function valueOfAlias() {
		var s = Target;
		return s.somefunc;
	}

	public static function callThroughValue() {
		var s = Target;
		var fn = s.somefunc;
		return fn();
	}

	public static function callDirect() {
		var s = Target;
		return s.somefunc();
	}

	public static function callWithArgument() {
		var s = Target;
		return s.twice(3);
	}

	public static function staticField() {
		var s = Target;
		return s.count;
	}

	static function getCls()
		return Target;

	/** Upstream types this through getCls's statics result; hxhx keeps today's dynamic call. */
	public static function sideEffectReceiver()
		return getCls().somefunc();
}
