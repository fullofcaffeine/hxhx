/** Decreases a counter through the other compilation unit. */
class CycleLeft {
	public static final tag:String = "ready";
	public static final base:Int = 0;
	public static final enabled:Bool = true;

	public static function value(n:Int):Int {
		if (enabled && n == 0)
			return base;
		return CycleRight.value(n - 1) + 1;
	}
}
