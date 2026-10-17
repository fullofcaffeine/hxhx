/** Record extension extraction so disabled or repeated calls cannot satisfy the observer. */
class Extractors {
	public static function isEven(value:Int):Bool {
		Main.events += "even;";
		return value % 2 == 0;
	}
}
