/**
	Observe local compound assignments, such as `x -= 2`, used as values.

	In Haxe a compound assignment is an expression: it stores the updated value
	in the local and produces that same value, typed like the local. The old
	value is read before the right operand runs, so `y += (y += 5)` adds the
	right operand to the value `y` had before the nested update.

	The fixture covers `Int`, `Float`, `Null<Int>`, `Null<Float>`, `String`, and
	`Dynamic` locals, in initializers, nested arithmetic, call arguments, and a
	`while` condition. Upstream Haxe and the native OCaml program must print the
	same lines.
 */
class Main {
	// Counted through an array: native static variable increments are a separate gap (haxe_ocaml-nq65n).
	static final sideCalls:Array<Int> = [];

	static function side(value:Int):Int {
		sideCalls.push(1);
		Sys.println("side " + Std.string(sideCalls.length));
		return value;
	}

	static function twice(value:Int):Int {
		return value * 2;
	}

	static function main():Void {
		var x = 4;
		final lowered = (x -= 2);
		Sys.println("int -= " + Std.string(lowered) + " " + Std.string(x));
		final raised = (x += 5);
		final scaled = (x *= 3);
		final remainder = (x %= 4);
		Sys.println("int += *= %= " + Std.string(raised) + " " + Std.string(scaled) + " " + Std.string(remainder) + " " + Std.string(x));

		// Each value is bound before printing: native String concatenation runs its
		// operands right to left, a separate gap (haxe_ocaml-5of2v).
		var w = 1;
		final nested = (w += 1) * 10;
		Sys.println("nested " + Std.string(nested) + " " + Std.string(w));
		final argument = twice(w -= side(3));
		Sys.println("argument " + Std.string(argument) + " " + Std.string(w));

		var y = 10;
		final ordered = (y += (y += 5));
		Sys.println("old value first " + Std.string(ordered) + " " + Std.string(y));

		var i = 0;
		while ((i += 1) < 3)
			Sys.println("loop " + Std.string(i));
		Sys.println("loop end " + Std.string(i));

		var f = 1.5;
		final floatRaised = (f += 2);
		final floatHalved = (f /= 4);
		Sys.println("float += /= " + Std.string(floatRaised) + " " + Std.string(floatHalved) + " " + Std.string(f));
		final floatScaled = (f *= side(3));
		final floatRest = (f %= 2);
		Sys.println("float *= %= " + Std.string(floatScaled) + " " + Std.string(floatRest) + " " + Std.string(f));
		var g = 0.5;
		final floatOrdered = (g += (g += 0.25));
		Sys.println("float old value first " + Std.string(floatOrdered) + " " + Std.string(g));

		var count:Null<Int> = 4;
		final counted = (count += 2);
		Sys.println("nullable int += " + Std.string(counted) + " " + Std.string(count) + " " + Std.string(counted == null));
		final countedDown = (count -= side(1));
		Sys.println("nullable int -= " + Std.string(countedDown) + " " + Std.string(count));

		var ratio:Null<Float> = 1.5;
		final ratioScaled = (ratio *= 3);
		Sys.println("nullable float *= " + Std.string(ratioScaled) + " " + Std.string(ratio));

		var missing:Null<Int> = null;
		try {
			final never = (missing += side(1));
			Sys.println("unexpected " + Std.string(never));
		} catch (error:Dynamic) {
			Sys.println("null update threw; still null " + Std.string(missing == null));
		}

		var text = "a";
		final appended = (text += "b");
		final appendedNumber = (text += 3);
		Sys.println("string += " + appended + " " + appendedNumber + " " + text);
		var word = "a";
		final wordOrdered = (word += (word += "b"));
		Sys.println("string old value first " + wordOrdered + " " + word);

		var dynamicValue:Dynamic = 1;
		final dynamicRaised = (dynamicValue += 2);
		Sys.println("dynamic += " + Std.string(dynamicRaised) + " " + Std.string(dynamicValue));
	}
}
