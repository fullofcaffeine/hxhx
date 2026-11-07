/**
	Calls `Array.concat` with every operand shape the OCaml target must handle.

	`concat` returns a new array. Changing the result must not change either
	operand, and changing an operand must not change the result. Each line
	prints the result and both operands, so a shared or truncated array shows
	up as a difference from upstream Haxe.
**/
class Point {
	public var x:Int;

	public function new(x:Int) {
		this.x = x;
	}
}

class Main {
	static var trace:Array<String> = [];

	static function prepend(args:Array<Dynamic>):Array<Dynamic> {
		return [null].concat(args);
	}

	static function left():Array<Int> {
		trace.push("left");
		return [1, 2];
	}

	static function right():Array<Int> {
		trace.push("right");
		return [3];
	}

	static function ints(values:Array<Int>):String {
		return values.join(",");
	}

	static function main():Void {
		final result = prepend([7]);
		Sys.println(result.length);
		Sys.println(result[0]);
		Sys.println(result[1]);

		final a = [1, 2];
		final b = [3];
		final joined = a.concat(b);
		joined[0] = 100;
		joined.push(4);
		a.push(5);
		b[0] = 30;
		Sys.println("ints " + ints(joined) + " a " + ints(a) + " b " + ints(b));

		final self = a.concat(a);
		self[0] = -1;
		Sys.println("self " + ints(self) + " a " + ints(a));

		final empty:Array<Int> = [];
		final leftEmpty = empty.concat([8, 9]);
		final rightEmpty = a.concat([]);
		final bothEmpty = empty.concat(empty);
		rightEmpty[0] = 0;
		bothEmpty.push(1);
		Sys.println("empty " + ints(leftEmpty) + " | " + ints(rightEmpty) + " | " + ints(bothEmpty) + " | " + empty.length + " a " + ints(a));

		final floats = [1.5, 2.25].concat([-0.5]);
		floats[1] = 0.125;
		Sys.println("floats " + floats.join(",") + " length " + floats.length);

		final words = ["x"].concat(["y", "z"]);
		words[0] = "w";
		Sys.println("strings " + words.join(","));

		final p = new Point(1);
		final points = [p].concat([new Point(2)]);
		points[0].x = 10;
		points[0] = new Point(99);
		Sys.println("objects " + points[0].x + "," + points[1].x + " original " + p.x);

		final inner = [1];
		final nested = [inner].concat([[2, 3], []]);
		nested[0].push(9);
		nested[1] = [4];
		Sys.println("nested "
			+ nested.length
			+ " "
			+ ints(nested[0])
			+ " "
			+ ints(nested[1])
			+ " "
			+ nested[2].length + " inner " + ints(inner));

		final mixed:Array<Null<Int>> = [null, 1];
		final mixedResult = mixed.concat([2, null]);
		Sys.println("nullable " + mixedResult.length + " " + mixedResult[0] + " " + mixedResult[1] + " " + mixedResult[3]);

		final ordered = left().concat(right());
		Sys.println("effects " + trace.join(",") + " " + ints(ordered));
	}
}
