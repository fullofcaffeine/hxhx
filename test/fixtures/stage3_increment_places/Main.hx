import haxe.Int32;

/**
	`++` and `--` on array elements, instance fields, and anonymous-structure fields.

	Covers prefix and postfix forms, statement and value positions, and `Int`,
	`Float`, `Int32`, and `Null<Int>` array elements. The array and index
	expressions must run exactly once, in source order. Each value-position
	result is stored in a local before printing, so the output does not depend
	on String concatenation operand order (Bead haxe_ocaml-b544p). Float values
	stay non-whole, so the output does not depend on whole-number Float text
	(Bead haxe_ocaml-iffj5).
**/
class Counter {
	public var count:Int = 0;
	public var level:Float = 0.5;

	public function new() {}
}

class Main {
	static var calls:Array<String> = [];

	static function pick(label:String, index:Int):Int {
		calls.push(label);
		return index;
	}

	static function source(values:Array<Int>):Array<Int> {
		calls.push("array");
		return values;
	}

	static function main():Void {
		final ints = [1, 2, 3];
		var j = 1;
		ints[j]++;
		ints[0]++;
		++ints[2];
		Sys.println("int statements: " + ints.join(","));
		final postfix = ints[0]--;
		final prefix = --ints[1];
		Sys.println("int values: " + postfix + " " + prefix + " " + ints.join(","));

		final floats = [1.5, 2.5];
		floats[0]++;
		final floatPrefix = --floats[1];
		Sys.println("float: " + floats[0] + " " + floatPrefix + " " + floats[1]);

		final wide:Array<Int32> = [7, 8];
		wide[0]++;
		final widePostfix = wide[1]--;
		Sys.println("int32: " + wide.join(",") + " " + widePostfix);

		final nullable:Array<Null<Int>> = [5, 6];
		nullable[0]++;
		final nullablePrefix = ++nullable[1];
		Sys.println("null element: " + nullable.join(",") + " " + nullablePrefix);

		final once = [10, 20];
		source(once)[pick("index", 1)]++;
		Sys.println("evaluated once: " + once.join(",") + " " + calls.join(","));

		final counter = new Counter();
		counter.count++;
		++counter.count;
		final countPostfix = counter.count--;
		counter.level++;
		final levelPrefix = --counter.level;
		Sys.println("fields: " + counter.count + " " + countPostfix + " " + counter.level + " " + levelPrefix);

		final shape = {k: 1, ratio: 0.25};
		shape.k++;
		final shapePrefix = ++shape.k;
		shape.ratio++;
		Sys.println("anonymous: " + shape.k + " " + shapePrefix + " " + shape.ratio);

		var total = 0;
		for (i in 0...ints.length)
			total += ints[i]++;
		Sys.println("loop: " + total + " " + ints.join(","));
	}
}
