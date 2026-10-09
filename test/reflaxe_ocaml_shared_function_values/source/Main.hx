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

	public static function invoke(hx_arg:Int, other:Int):Int
		return choose(choose(hx_arg, other), other);

	public static function scoped(value:Int):Int {
		{
			final value = 9;
			value;
		}
		return value;
	}

	public static function done():Void {
		return;
	}

	static function main():Void {
		choose(7, 9);
		logical(false);
		text("hé\x00z");
		invoke(3, 5);
		scoped(8);
		done();
	}
}
