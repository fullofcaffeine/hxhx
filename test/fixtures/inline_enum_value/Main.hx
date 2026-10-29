enum Token {
	Item(value:Int);
}

/** Saving an inline EnumValue parameter must preserve the concrete enum object and evaluate its source once. */
class Main {
	static var calls:Int = 0;
	static var last:Token;

	static function next():Token {
		calls++;
		last = Token.Item(7);
		return last;
	}

	static extern inline function identity(value:EnumValue):EnumValue {
		return value;
	}

	static function main():Void {
		final value = identity(next());
		if (value != last || calls != 1)
			throw "inline enum identity or evaluation count changed";
		js.Syntax.code("console.log('INLINE_ENUM_VALUE_RUNTIME:PASS')");
	}
}
