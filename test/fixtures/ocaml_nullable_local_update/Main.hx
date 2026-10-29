/**
	Observe increments, decrements, and compound assignments on nullable Int and
	Float locals, including a nested `Null<Null<Int>>` declaration.

	Each update reads the stored value, computes the next number, and stores it
	back. A postfix update produces the old number and a prefix update the new
	one; both are plain numbers rather than nullable values. Updating a null
	`Null<Int>` throws before anything is stored, so the local stays null.
	Upstream Haxe's interpreter reports an increment as "Null Access" but a
	decrement as "Invalid operation: null - 1"; the native program raises Null
	Access for both, so the decrement case prints only that it threw.
	Upstream Haxe and the native OCaml program must print the same lines.
 */
class Main {
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
	}
}
