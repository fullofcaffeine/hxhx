/** A runtime Boolean result from enum equality must use the same output conversion. */
enum Signal {
	Value(number:Int);
}

/** Console conversion preserves Boolean text and evaluates each argument once. */
class Main {
	static var calls:Int = 0;

	static function nextValue():Bool {
		calls++;
		return calls == 1;
	}

	static function main():Void {
		Sys.println(true);
		Sys.println(false);
		var value:Bool = false;
		Sys.println(value);
		Sys.print(nextValue());
		Sys.print("|");
		Sys.println(nextValue());
		Sys.println(calls);
		Sys.println("text");
		Sys.println(42);
		Sys.println(1.5);
		Sys.println(null);
		Sys.print(true);
		Sys.print(false);
		Sys.println("");
		Sys.println(Type.enumEq(Signal.Value(7), Signal.Value(7)));
		Sys.println(Type.enumEq(Signal.Value(7), Signal.Value(8)));
	}
}
