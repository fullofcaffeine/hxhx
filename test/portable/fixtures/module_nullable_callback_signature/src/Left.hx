/** Nullable callback declarations remain available inside a recursive module group. */
class Left {
	public function new(?setup:Void->Void) {
		if (setup != null)
			setup();
	}

	public function apply(value:Int, ?callback:Int->Int):Int {
		return callback == null ? value : callback(value);
	}

	public static function factory(enabled:Bool):Null<Int->Int> {
		return enabled ? value -> Right.value(value) : null;
	}

	public static function value(n:Int):Int {
		return n == 0 ? 0 : Right.value(n - 1) + 1;
	}
}
