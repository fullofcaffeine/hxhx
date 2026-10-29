/** A literal-bearing module cannot anchor a recursive initialization cycle. */
class CycleLeft {
	public static final tag:String = "left";

	public static function value(n:Int):String {
		return n == 0 ? tag : CycleRight.value(n - 1);
	}
}
