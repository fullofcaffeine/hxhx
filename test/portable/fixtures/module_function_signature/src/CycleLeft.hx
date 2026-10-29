/** Exercises a represented static function signature without a module cycle. */
class CycleLeft {
	public static function value(n:Int):Int {
		if (n == 0)
			return 0;
		return CycleRight.value(n - 1) + 1;
	}
}
