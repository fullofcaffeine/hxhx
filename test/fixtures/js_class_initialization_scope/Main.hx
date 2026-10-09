/** JavaScript startup declarations share the generated program's lexical scope. */
class Main {
	static var captured:Void->Int;

	static function __init__():Void {
		// Target syntax is intentional: this tests the scope promised to host declarations.
		js.Syntax.code("var startupToken = { value: 7 };");
		final value = 7;
		captured = () -> value;
	}

	static function read():Int {
		return js.Syntax.code("startupToken.value");
	}

	static function main():Void {
		if (read() != 7)
			throw "startup declaration is not shared";
		if (captured() != 7 || Other.read() != 9)
			throw "startup locals share captured storage";
		// Haxe 4.3.7 emits both startup declarations in one program scope.
		if (CollisionFirst.read() != 11 || CollisionSecond.read() != 11)
			throw "startup scope differs from upstream";
	}
}

/** Upstream startup locals share a scope, including same-name captured declarations. */
class CollisionFirst {
	static var captured:Void->Int;

	static function __init__():Void {
		final sharedValue = 10;
		captured = () -> sharedValue;
	}

	public static function read():Int
		return captured();
}

/** The second declaration determines what both startup callbacks later observe. */
class CollisionSecond {
	static var captured:Void->Int;

	static function __init__():Void {
		final sharedValue = 11;
		captured = () -> sharedValue;
	}

	public static function read():Int
		return captured();
}

/** A second startup must preserve its independently captured value. */
class Other {
	static var captured:Void->Int;

	static function __init__():Void {
		final otherValue = 9;
		captured = () -> otherValue;
	}

	public static function read():Int {
		return captured();
	}
}
