/**
	Observe local compound assignments, such as `x -= 2`, used as values.

	In Haxe a compound assignment is an expression: it stores the updated value
	in the local and produces that same value, typed like the local. The old
	value is read before the right operand runs, so `y += (y += 5)` adds the
	right operand to the value `y` had before the nested update.

	The fixture covers `Int`, `Float`, `Null<Int>`, `Null<Float>`, `String`, and
	`Dynamic` locals, in initializers, nested arithmetic, call arguments,
	operators that consume the value, and `while` conditions. Statement-position
	updates are checked for the same old-value-first order. Upstream Haxe and the
	native OCaml program must print the same lines.
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

		// An operator that consumes the value must see the local's type.
		var pair = 1;
		final pairSum = (pair += 1) + (pair += 1);
		Sys.println("int operands " + Std.string(pairSum) + " " + Std.string(pair));
		final widened = 0.25 * (pair += 2);
		Sys.println("int operand of float " + Std.string(widened) + " " + Std.string(pair));
		var scale = 1.25;
		final scaled = (scale += 1) * 2;
		Sys.println("float operand " + Std.string(scaled) + " " + Std.string(scale));
		var stock:Null<Int> = 4;
		final stockProduct = (stock += 2) * 3;
		var steps = 0;
		while ((stock += 1) < 9)
			steps++;
		Sys.println("nullable int operand " + Std.string(stockProduct) + " " + Std.string(steps) + " " + Std.string(stock));
		var share:Null<Float> = 1.5;
		final shareLarge = (share *= 3) > 4;
		Sys.println("nullable float operand " + Std.string(shareLarge) + " " + Std.string(share));
		var label = "s";
		final labelText = (label += "t") + "!";
		Sys.println("string operand " + labelText + " " + label);

		// A numeric right operand is added before it is appended: "p" + (1 + 2).
		var sum = "p";
		final sumValue = (sum += 1 + 2);
		var sumStatement = "q";
		sumStatement += 1 + 2;
		var flag = "f";
		final flagValue = (flag += 1 > 0);
		Sys.println("string numeric right operand " + sumValue + " " + sum + " " + sumStatement + " " + flagValue);

		// Statement-position updates also read the old value before the right operand.
		var counter = 10;
		counter += (counter += 5);
		var fraction = 0.5;
		fraction += (fraction += 0.25);
		var letters = "a";
		letters += (letters += "b");
		var calls = 1;
		function bump():Int {
			calls += 10;
			return 1;
		}
		calls += bump();
		Sys.println("statement old value first "
			+ Std.string(counter)
			+ " "
			+ Std.string(fraction)
			+ " "
			+ letters
			+ " "
			+ Std.string(calls));
	}
}
