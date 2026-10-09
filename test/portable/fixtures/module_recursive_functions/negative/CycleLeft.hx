/** An eager cross-module initializer needs a broader initialization model. */
class CycleLeft {
	public static var boot:Int = CycleRight.value(0);

	public static function value(n:Int):Int {
		return n == 0 ? 0 : CycleRight.value(n - 1) + 1;
	}
}
