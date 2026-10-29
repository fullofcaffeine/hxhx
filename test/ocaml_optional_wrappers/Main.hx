/** Optional defaults and argument effects survive expression wrappers. */
class Main {
	static function argument():Int {
		Sys.println("argument");
		return 7;
	}

	static function read(value:Int, extra:Int = 23):Int {
		return value + extra;
	}

	static function main():Void {
		final direct = read(argument());
		final parenthesized = (read(argument()));
		final annotated = (read(argument()) : Int);
		final converted:Int = cast read(argument());
		// Exercise the language's untyped wrapper at its explicit test boundary.
		final unchecked:Int = untyped read(argument());
		Sys.println(direct);
		Sys.println(parenthesized);
		Sys.println(annotated);
		Sys.println(converted);
		Sys.println(unchecked);
	}
}
