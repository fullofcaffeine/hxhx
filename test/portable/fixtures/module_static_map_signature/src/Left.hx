/** Counts keys without changing the generic map's existing element storage. */
class Left {
	public static function count<T>(values:haxe.ds.StringMap<T>):Int {
		if (values == null)
			return 0;
		var count = 0;
		for (_ in values.keys())
			count++;
		return Right.value(count);
	}

	public static function value(n:Int):Int {
		return n == 0 ? 0 : Right.value(n - 1) + 1;
	}
}
