/** Ordinary arguments and results that must cross the shared target boundary unchanged. */
class Main {
	public static function choose(first:Int, second:Int):Int {
		final copy = first;
		return copy;
	}

	public static function logical(value:Bool):Bool
		return value;

	public static function text(value:String):String
		return value;

	static function main():Void {
		choose(7, 9);
		logical(false);
		text("hé\x00z");
	}
}
