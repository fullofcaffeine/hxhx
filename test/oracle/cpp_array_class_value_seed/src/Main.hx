/** Array class values erase element arguments; ordinary array values do not. */
class Main {
	static final selected:Class<Array<Bool>> = Array;

	static function pick():Class<Array<Bool>> {
		return Array;
	}

	static function identity(value:Class<Array<Bool>>):Class<Array<Bool>> {
		return value;
	}

	static function acceptsGeneric(value:Class<Holder<String>>):Bool {
		return value == Holder;
	}

	static function main():Void {
		// Dynamic appears only in the language's erased Array class-value type.
		final erased:Class<Array<Dynamic>> = selected;
		Sys.println(selected == Array);
		Sys.println(pick() == Array);
		Sys.println(identity(Array) == Array);
		Sys.println(erased == Array);
		var alias = Array;
		final strings:Class<Array<String>> = alias;
		final booleans:Class<Array<Bool>> = alias;
		Sys.println(strings == Array);
		Sys.println(booleans == Array);
		alias = null;
		Sys.println(alias == null);
		final generic = Holder;
		final integers:Class<Holder<Int>> = generic;
		final texts:Class<Holder<String>> = generic;
		final erasedGeneric:Class<Dynamic> = generic;
		Sys.println(integers == Holder);
		Sys.println(texts == Holder);
		Sys.println(erasedGeneric == Holder);
		Sys.println(acceptsGeneric(generic));
	}
}

/** Ordinary generic declarations use the same descriptor contract as core Array. */
class Holder<T> {}
