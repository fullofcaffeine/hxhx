/** Metadata changes compiler policy without adding a runtime call or repeating its value. */
class Main {
	static var calls:Int = 0;

	static function tick(value:Int):Int {
		calls++;
		return value;
	}

	static function early():Int {
		@:probe return tick(5);
	}

	static function main():Void {
		final first = @:first @:second tick(4);
		final second = @:nullSafety(Off) tick(3);
		if (first + second != 7 || calls != 2)
			throw "metadata value or evaluation count";
		if (early() != 5 || calls != 3)
			throw "metadata return target";
	}
}
