/** An ordinary same-named method must keep its own implementation. */
class PushSink {
	public function new() {}

	public function push(value:Int):Int
		return value + 100;
}

/** Saved Array methods retain the original container and run only when called. */
class Main {
	static function receiver(values:Array<Int>):Array<Int> {
		Sys.println("receiver");
		return values;
	}

	static function main():Void {
		var values = [2];
		final original = values;
		final append = receiver(values).push;
		values = [9];
		Sys.println(append(3));
		Sys.println(append(5));
		Sys.println(original.length);
		Sys.println(original[1]);
		Sys.println(original[2]);
		Sys.println(values[0]);

		var chosen = original;
		final size = receiver(chosen).push({
			Sys.println("argument");
			chosen = [11];
			4;
		});
		Sys.println(size);
		Sys.println(original[3]);
		Sys.println(chosen[0]);

		var mixed:Array<Dynamic> = [];
		final store = mixed.push;
		Sys.println(store(true));
		Sys.println(store(false));
		Sys.println(Std.string(mixed[0]));
		Sys.println(Std.string(mixed[1]));

		final userMethod = new PushSink().push;
		Sys.println(userMethod(5));
	}
}
