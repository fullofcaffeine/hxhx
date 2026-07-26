/** Executable proof that the argument is evaluated once before the callee. */
class Main {
	static function sourceValue():Int {
		Sys.println("argument");
		return 41;
	}

	static function main():Void {
		final result = Arithmetic.increment(sourceValue());
		Sys.println("result=" + result);
		Sys.println("two=" + Arithmetic.add(1, 2));
		Sys.println("instance=" + new Counter().increment(5));
	}
}
