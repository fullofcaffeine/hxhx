/**
	Observe increments, decrements, and compound assignments on nullable Int and
	Float locals, including a nested `Null<Null<Int>>` declaration.

	Each update reads the stored value, computes the next number, and stores it
	back. A postfix update produces the old number and a prefix update the new
	one; both are plain numbers rather than nullable values. Updating a null
	`Null<Int>` or `Null<Float>` throws before anything is stored, so the local
	stays null. A right operand still runs before the throw.

	Upstream Haxe's interpreter reports "Null Access" only when a null is
	stepped by the literal 1 (`n++`, `++n`, `n += 1`). Other shapes, such as a
	decrement or `n += 2`, report "Invalid operation: null - 1" or similar. The
	native program raises Null Access for every null update, so those other
	cases print only that the update threw.
	Upstream Haxe and the native OCaml program must print the same lines.
 */
class Main {
	// Counted through an array: native static variable increments are a separate gap (haxe_ocaml-nq65n).
	static final sideCalls:Array<Int> = [];

	static function side():Int {
		sideCalls.push(1);
		Sys.println("side " + Std.string(sideCalls.length));
		return 2;
	}

	static function sideFloat():Float {
		sideCalls.push(1);
		Sys.println("side float " + Std.string(sideCalls.length));
		return 0.5;
	}

	static function main():Void {
		var count:Null<Int> = 4;
		final old:Int = count++;
		Sys.println(Std.string(old) + " " + Std.string(count));
		final next = ++count;
		Sys.println(Std.string(next) + " " + Std.string(count));
		final before = count--;
		--count;
		Sys.println(Std.string(before) + " " + Std.string(count));
		count++;
		count += 3;
		count -= 1;
		count *= 2;
		Sys.println(Std.string(count) + " " + Std.string(count == 14));

		var ratio:Null<Float> = 1.5;
		final oldRatio = ratio++;
		Sys.println(Std.string(oldRatio) + " " + Std.string(ratio));
		final lowered = --ratio;
		ratio += 1;
		ratio *= 0.5;
		Sys.println(Std.string(lowered) + " " + Std.string(ratio));

		var plain:Float = 0.25;
		final oldPlain = plain++;
		--plain;
		plain--;
		Sys.println(Std.string(oldPlain) + " " + Std.string(plain));

		var nested:Null<Null<Int>> = 4;
		final oldNested = nested++;
		final nextNested = ++nested;
		nested += 10;
		Sys.println(Std.string(oldNested) + " " + Std.string(nextNested) + " " + Std.string(nested));
		nested = null;
		Sys.println(Std.string(nested == null));

		var missing:Null<Int> = null;
		try {
			final observed = missing++;
			Sys.println("postfix produced " + Std.string(observed));
		} catch (error:Dynamic) {
			Sys.println("postfix " + Std.string(error));
		}
		try {
			final observed = ++missing;
			Sys.println("prefix produced " + Std.string(observed));
		} catch (error:Dynamic) {
			Sys.println("prefix " + Std.string(error));
		}
		try {
			missing += 1;
			Sys.println("compound produced " + Std.string(missing));
		} catch (error:Dynamic) {
			Sys.println("compound " + Std.string(error));
		}
		Sys.println(Std.string(missing));

		var missingNested:Null<Null<Int>> = null;
		try {
			missingNested--;
			Sys.println("nested produced " + Std.string(missingNested));
		} catch (error:Dynamic) {
			Sys.println("nested decrement threw");
		}
		Sys.println(Std.string(missingNested));

		var missingRatio:Null<Float> = null;
		try {
			missingRatio++;
			Sys.println("float postfix produced " + Std.string(missingRatio));
		} catch (error:Dynamic) {
			Sys.println("float postfix " + Std.string(error));
		}
		try {
			missingRatio += 1;
			Sys.println("float compound produced " + Std.string(missingRatio));
		} catch (error:Dynamic) {
			Sys.println("float compound " + Std.string(error));
		}
		Sys.println(Std.string(missingRatio));

		try {
			missing += side();
			Sys.println("side compound produced " + Std.string(missing));
		} catch (error:Dynamic) {
			Sys.println("side compound threw");
		}
		try {
			final sum = missing + side();
			Sys.println("side sum produced " + Std.string(sum));
		} catch (error:Dynamic) {
			Sys.println("side sum threw");
		}
		try {
			missingRatio += sideFloat();
			Sys.println("side float compound produced " + Std.string(missingRatio));
		} catch (error:Dynamic) {
			Sys.println("side float compound threw");
		}
		var present:Null<Int> = 1;
		present += side();
		final presentSum = present * side();
		Sys.println(Std.string(present) + " " + Std.string(presentSum) + " " + Std.string(sideCalls.length));
	}
}
