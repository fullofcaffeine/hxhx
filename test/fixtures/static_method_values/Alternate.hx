/** Distinct output exposes accidental binding to the same-named method. */
class Alternate {
	public static function choose(value:Int):Int {
		return value + 100;
	}
}
