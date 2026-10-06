/** Array class values erase element arguments; ordinary array values do not. */
class Main {
	static final selected:Class<Array<Bool>> = Array;

	static function pick():Class<Array<Bool>> {
		return Array;
	}

	static function identity(value:Class<Array<Bool>>):Class<Array<Bool>> {
		return value;
	}

	static function main():Void {
		// Dynamic appears only in the language's erased Array class-value type.
		final erased:Class<Array<Dynamic>> = selected;
		Sys.println(selected == Array);
		Sys.println(pick() == Array);
		Sys.println(identity(Array) == Array);
		Sys.println(erased == Array);
	}
}
