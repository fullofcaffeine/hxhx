/** The value-level dependency back to Cache makes the module cycle observable. */
class Peer {
	public static function twice(value:Int):Int
		return value * 2;

	public static function calculate(value:Int):Int
		return Cache.get().apply(value);
}
