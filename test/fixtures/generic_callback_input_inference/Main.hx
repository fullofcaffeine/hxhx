/**
	An omitted input passed where a generic method expects a callback over its type parameter takes
	the callback type from the binding, as in Haxe 4.3.7. The operations live in their own class,
	declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Walk {
	public static function check<T>(value:T, test:T->Bool):Bool
		return test(value);

	// The shape of `haxe.ds.ArraySort.rec`: the omitted `test` becomes `T->Bool` through
	// `check`, then the recursive call passes it back to this method's own input.
	public static function count<T>(value:T, test, times:Int):Int {
		if (times == 0)
			return 0;
		final hit = check(value, test) ? 1 : 0;
		return hit + count(value, test, times - 1);
	}
}

class Ops {
	// `test` takes `Int->Bool` from `check<T>(value:T, test:T->Bool)` with `T` bound to Int.
	public static function anyPositive(items:Array<Int>, test) {
		var found = false;
		for (item in items)
			if (Walk.check(item, test))
				found = true;
		return found;
	}

	public static function repeat(value:Int, times:Int)
		return Walk.count(value, n -> n > 0, times);
}

class Main {
	static function main() {
		Sys.println(Ops.anyPositive([-1, 2], n -> n > 0));
		Sys.println(Ops.anyPositive([-1, -2], n -> n > 0));
		Sys.println(Ops.repeat(5, 3));
	}
}
