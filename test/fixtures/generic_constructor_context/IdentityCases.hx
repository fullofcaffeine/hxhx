/** Independent occurrences, aliases, and lexical shadowing must retain distinct inferred arguments. */
class IdentityCases {
	static function text(value:Box<String>):String {
		return "string";
	}

	static function number(value:Box<Int>):String {
		return "int";
	}

	static function make():Box<String> {
		return new Box();
	}

	static function main():Void {
		final outer = new Box();
		final alias = outer;
		Sys.println(text(alias));
		final other = new Box();
		Sys.println(number(other));
		{
			final outer = new Box();
			Sys.println(number(outer));
		}
		Sys.println(text(outer));
		Sys.println(text(new Box()));
		Sys.println(text(make()));
		final written:Box<String> = new Box();
		Sys.println(text(written));
	}
}

/** The same declaration must not merge the arguments of independent allocations. */
class Box<T> {
	public function new() {}
}
