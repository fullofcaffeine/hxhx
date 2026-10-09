/** Each handler entry owns a distinct mutable binding, shared only with its escaping closure. */
class Main {
	public static function capture(seed:Dynamic):Dynamic->Dynamic {
		final input = seed;
		try {
			throw input;
		} catch (state:Dynamic) {
			return function(next:Dynamic):Dynamic {
				final previous = state;
				state = next;
				return previous;
			};
		}
	}

	public static function plain(seed:Dynamic):Dynamic {
		try {
			throw seed;
		} catch (value:Dynamic) {
			return value;
		}
	}

	static function main():Void {
		final first = capture("first");
		final second = capture("second");
		if (first("changed") != "first" || second(null) != "second" || first(null) != "changed")
			throw "handler entries shared or lost their mutable binding";
		if (plain("plain") != "plain" || plain(null) != null)
			throw "uncaptured catch changed its value";
	}
}
