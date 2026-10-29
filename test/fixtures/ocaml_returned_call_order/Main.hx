/** Returned Dynamic callables keep factory arity separate from invocation arity. */
class Main {
	static function zero():Int
		return 7;

	static function pair(left:Int, right:Int):Int
		return left * 10 + right;

	static function factory(mode:Int, label:String):Dynamic {
		Sys.println(label);
		if (mode == 0)
			return zero;
		return pair;
	}

	static function mark(value:Int):Int {
		Sys.println(value);
		return value;
	}

	static function shadow(factory:(Int, Int) -> Int):Int
		return factory(3, 4);

	static function main():Void {
		Sys.println(factory(0, "zero-factory")());
		Sys.println(factory(2, "pair-factory")(mark(1), mark(2)));
		Sys.println(Main.factory(2, "qualified-factory")(mark(5), mark(6)));
		Sys.println(shadow(pair));
	}
}
