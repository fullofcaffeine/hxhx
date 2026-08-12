/** Exercises sealed exact integer unary operations through generated OCaml. */
class Main {
	static var calls = 0;
	static var standaloneSeed = 1;
	static final standalone = ~standaloneSeed;

	/** Returns one exact Int and records how often the unary operand is evaluated. */
	static function next():Int {
		calls++;
		return 7;
	}

	static function main():Void {
		final exact:Int = 7;
		final minimum:Int = 0x80000000;
		final nullableNull:Null<Int> = null;
		final nullableValue:Null<Int> = 5;
		final nestedSeed = 2;
		final nested = () -> ~nestedSeed;

		Sys.println("literal=" + -9);
		Sys.println("neg=" + -exact);
		Sys.println("not=" + ~exact);
		Sys.println("min=" + -minimum);
		Sys.println("side=" + -next());
		Sys.println("calls=" + calls);
		Sys.println("null.neg=" + -nullableNull);
		Sys.println("null.not=" + ~nullableNull);
		Sys.println("value.neg=" + -nullableValue);
		Sys.println("value.not=" + ~nullableValue);
		Sys.println("nested=" + nested());
		Sys.println("standalone=" + standalone);
	}
}
