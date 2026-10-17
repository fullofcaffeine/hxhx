package other;

/** A same-named provider must not replace the selected package owner. */
class Api {
	public static function combine(left:String, right:String):String {
		return "other:" + left + ":" + right;
	}
}
