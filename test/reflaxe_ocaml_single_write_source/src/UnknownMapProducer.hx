/** A user method with the same result type must not impersonate the native getter. */
class UnknownMapProducer {
	public static function get():Null<Map<Int, String>> {
		return null;
	}
}
