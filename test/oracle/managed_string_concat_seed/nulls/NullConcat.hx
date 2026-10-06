/** Preserve null String behavior through the native callable boundary. */
class NullConcat {
	public static function combine(left:String, right:String):String {
		return left + right;
	}
}
