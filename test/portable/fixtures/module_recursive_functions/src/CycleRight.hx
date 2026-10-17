/** Returns through the original module path, including from outside the group. */
class CycleRight {
	public static function value(n:Int):Int {
		if (n == 0)
			return 0;
		return CycleLeft.value(n - 1) + 1;
	}
}
