import haxe.Int32;

/**
	`++` and `--` on array elements, instance fields, and anonymous-structure fields.

	Covers prefix and postfix forms, statement and value positions, `Int`,
	`Float`, `Int32`, `Null<Int>`, and `Null<Float>` array elements, `Null<Int>`
	and `Null<Float>` fields (including the postfix and prefix results of
	nullable slots), a nested index, Int overflow wrap, and a null element
	(which throws, as on upstream eval). The array and index
	expressions, and a field receiver call, must run exactly once, in source
	order. The receiver check records calls in an array, because `++` on a
	static field is a separate fix (PR #131). Each value-position
	result is stored in a local before printing, so the output does not depend
	on String concatenation operand order (Bead haxe_ocaml-b544p). Float values
	stay non-whole, so the output does not depend on whole-number Float text
	(Bead haxe_ocaml-iffj5).
**/
class Counter {
	public var count:Int = 0;
	public var level:Float = 0.5;
	public var maybe:Null<Int> = 40;
	public var maybeRatio:Null<Float> = 0.25;

	public function new() {}
}

class Main {
	static var calls:Array<String> = [];

	static function pick(label:String, index:Int):Int {
		calls.push(label);
		return index;
	}

	static function owner(counter:Counter):Counter {
		calls.push("owner");
		return counter;
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

		counter.maybe++;
		final maybePrefix = ++counter.maybe;
		counter.maybeRatio--;
		Sys.println("nullable fields: " + counter.maybe + " " + maybePrefix + " " + counter.maybeRatio);

		final before = calls.length;
		owner(counter).count++;
		Sys.println("receiver once: " + counter.count + " " + calls.slice(before).join(","));

		final nested = [0, 5, 7];
		nested[nested[0]++]++;
		Sys.println("nested index: " + nested.join(","));

		final cell = [3];
		final sum = cell[0]++ + cell[0];
		Sys.println("postfix then read: " + sum + " " + cell[0]);

		final big = [2147483647];
		big[0]++;
		final small = [-2147483648];
		small[0]--;
		Sys.println("overflow wrap: " + big[0] + " " + small[0]);

		final holes:Array<Null<Int>> = [null];
		try {
			holes[0]++;
			Sys.println("null element: " + holes[0]);
		} catch (e:Dynamic) {
			Sys.println("null element: threw");
		}

		final shape = {k: 1, ratio: 0.25};
		shape.k++;
		final shapePrefix = ++shape.k;
		shape.ratio++;
		Sys.println("anonymous: " + shape.k + " " + shapePrefix + " " + shape.ratio);

		var total = 0;
		for (i in 0...ints.length)
			total += ints[i]++;
		Sys.println("loop: " + total + " " + ints.join(","));

		final nullableOld:Array<Null<Int>> = [5, 6];
		final firstOld = nullableOld[0]++;
		final secondOld = nullableOld[1]--;
		Sys.println("null element postfix: " + firstOld + " " + secondOld + " " + nullableOld.join(","));

		final ratios:Array<Null<Float>> = [0.5, 1.5];
		ratios[0]++;
		final ratioPrefix = ++ratios[1];
		final ratioPostfix = ratios[0]--;
		Sys.println("null float element: " + ratioPrefix + " " + ratioPostfix + " " + ratios.join(","));

		final maybePostfix = counter.maybe++;
		final ratioFieldPrefix = ++counter.maybeRatio;
		final ratioFieldPostfix = counter.maybeRatio--;
		Sys.println("nullable field results: " + maybePostfix + " " + counter.maybe + " " + ratioFieldPrefix + " " + ratioFieldPostfix + " "
			+ counter.maybeRatio);
	}
}
