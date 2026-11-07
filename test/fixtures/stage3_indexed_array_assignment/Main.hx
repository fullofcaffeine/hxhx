/**
	Indexed array writes must change the real array storage.

	Each case prints the observable state after an `a[i] = v` statement so a
	dropped write, a write to a copy, or a reordered side effect is visible.
**/
class Main {
	static var trace:Array<String> = [];

	static function fill(values:Array<Null<Int>>):Void {
		values[1] = 7;
	}

	static function note(label:String, value:Int):Int {
		trace.push(label);
		return value;
	}

	static function receiver(values:Array<Int>):Array<Int> {
		trace.push("receiver");
		return values;
	}

	static function main():Void {
		// Nullable storage written through an alias passed to another function.
		var values:Array<Null<Int>> = [null, null];
		var alias = values;
		fill(alias);
		Sys.println(values.length);
		Sys.println(values[0]);
		Sys.println(values[1]);

		// Repeated writes to the same slot keep the last value.
		var ints = [1, 2, 3];
		ints[0] = 10;
		ints[0] = 20;
		ints[2] = ints[0];
		Sys.println(ints.join(","));

		// An indexed write used as a value yields the assigned value.
		var assigned = (ints[1] = 42);
		Sys.println(assigned);
		Sys.println(ints[1]);

		// Receiver, index, then value are each evaluated once, in source order.
		receiver(ints)[note("index", 1)] = note("value", 99);
		Sys.println(trace.join(">"));
		Sys.println(ints.join(","));

		// Writing past the end grows the array and fills the gap.
		var grow:Array<Null<Int>> = [];
		grow[2] = 5;
		Sys.println(grow.length);
		Sys.println(grow[0]);
		Sys.println(grow[2]);

		// String and Float element storage.
		var names = ["a", "b"];
		names[1] = "z";
		Sys.println(names.join(","));
		var floats = [1.5, 2.5];
		floats[0] = 0.25;
		Sys.println(floats[0]);
		Sys.println(floats[1]);

		// A write inside a loop body.
		var squares = [0, 0, 0, 0];
		for (i in 0...squares.length)
			squares[i] = i * i;
		Sys.println(squares.join(","));
	}
}
