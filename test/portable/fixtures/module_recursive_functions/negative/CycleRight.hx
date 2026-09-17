/** Completes the dependency cycle in the initialization counterexample. */
class CycleRight {
	public static function value(n:Int):Int {
		return n == 0 ? 0 : CycleLeft.value(n - 1) + 1;
	}
}
