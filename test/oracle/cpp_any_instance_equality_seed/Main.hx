/** A plain reference used to distinguish identity from stored field equality. */
class Token {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** Another allocation category must not acquire Token identity through Any. */
class Other {
	public function new() {}
}

/** An upcast must retain the same allocation through opaque storage. */
class Child extends Token {
	public function new() {
		super(8);
	}
}

/** Test declared opaque backing storage without depending on the standard Any name. */
abstract Opaque(Dynamic) from Dynamic {}

/** The compiler must select this authored operator before inspecting opaque storage. */
abstract NeverEqual(Dynamic) from Dynamic {
	@:op(A == B) public static function same(left:NeverEqual, right:Token):Bool {
		return false;
	}
}

/** Observe equality at an explicit opaque-value boundary, as used by Exception.native. */
class Main {
	public static var effects:Int = 0;

	static function allocatingLeft(fail:Bool):Any {
		effects = effects * 10 + 1;
		if (fail)
			throw "left";
		return new Token(1);
	}

	static function allocatingRight(fail:Bool):Token {
		effects = effects * 10 + 2;
		if (fail)
			throw "right";
		return new Token(1);
	}

	/** A thrown operand stops evaluation and releases any earlier temporary instance. */
	public static function compareFailure(failLeft:Bool, failRight:Bool):Bool {
		effects = 0;
		return allocatingLeft(failLeft) == allocatingRight(failRight);
	}

	static function left(value:Any):Any {
		effects = effects * 10 + 1;
		return value;
	}

	static function right(value:Token):Token {
		effects = effects * 10 + 2;
		return value;
	}

	static function observe(label:String, opaque:Any, token:Token, expected:Bool):Void {
		if ((opaque == token) != expected || (token == opaque) != expected || (opaque != token) == expected)
			throw label;
	}

	static function main():Void {
		final token = new Token(7);
		observe("alias", token, token, true);
		observe("different", new Token(7), token, false);
		observe("other-class", new Other(), token, false);
		observe("int", 7, token, false);
		observe("bool", true, token, false);
		observe("string", "value", token, false);
		observe("null", null, token, false);
		observe("both-null", null, null, true);
		observe("value-null", token, null, false);
		final child = new Child();
		final base:Token = child;
		observe("inherited", child, base, true);
		final custom:Opaque = token;
		if (custom != token || token != custom)
			throw "declared opaque storage";
		final overridden:NeverEqual = token;
		if (overridden == token)
			throw "authored operator was ignored";
		final opaque:Any = token;
		if (!(left(opaque) == right(token)) || effects != 12)
			throw "operand order";
		if (compareFailure(false, false) || effects != 12)
			throw "allocating operand order";
	}
}
