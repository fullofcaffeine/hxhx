/** Field initialization and its nested closures retain their own fresh catch variables. */
class Main {
	public var captured:Dynamic->Dynamic = try {
		throw "field";
	} catch (state:Dynamic) {
		function(next:Dynamic):Dynamic {
			final previous = state;
			state = next;
			return previous;
		};
	};

	public var plain:Dynamic = try {
		throw "plain";
	} catch (value:Dynamic) {
		value;
	};

	public var nested:Void->(Dynamic->Dynamic) = function():Dynamic->Dynamic {
		return try {
			throw "nested";
		} catch (state:Dynamic) {
			function(next:Dynamic):Dynamic {
				final previous = state;
				state = next;
				return previous;
			};
		};
	};

	public var nestedPlain:Void->Dynamic = function():Dynamic {
		try {
			throw "nested-plain";
		} catch (value:Dynamic) {
			return value;
		}
	};

	public function new() {}

	static function main():Void {
		final first = new Main();
		final second = new Main();
		if (first.captured("changed") != "field" || second.captured(null) != "field" || first.captured(null) != "changed")
			throw "field catch storage was shared or lost";
		final a = first.nested();
		final b = first.nested();
		if (a("changed") != "nested" || b(null) != "nested" || a(null) != "changed")
			throw "nested catch storage was shared or lost";
		if (first.plain != "plain" || first.nestedPlain() != "nested-plain")
			throw "uncaptured field catch changed its value";
	}
}
