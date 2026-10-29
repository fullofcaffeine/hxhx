/** Both members carry constants, so the compiler must reject this cycle. */
class CycleRight {
	public static final tag:String = "right";

	public static function value(n:Int):String {
		return n == 0 ? tag : CycleLeft.value(n - 1);
	}
}
