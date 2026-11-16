/**
	Block-bodied local functions and function expressions whose declared result
	is `Float`. Every printed value is a short binary fraction, so the output does
	not depend on how many digits a target prints for an inexact `Float`.
 */
class Main {
	static function main():Void {
		// A function expression that updates a captured outer local and returns a literal.
		var f = 0.5;
		final bump = function():Float {
			f += 1;
			return 0.25;
		};
		Sys.println(bump());
		Sys.println(f);

		// A local function declaration that assigns a captured local.
		function bumpF():Float {
			f = 100.25;
			return 0.25;
		}
		Sys.println(bumpF());
		Sys.println(f);

		// A result read from a local of the function itself.
		final half = function(value:Float):Float {
			final result = value / 2;
			return result;
		};
		Sys.println(half(7.0));

		// An arithmetic result that reads a captured local.
		var scale = 1.25;
		final scaled = function(value:Float):Float {
			return value * scale + 0.25;
		};
		Sys.println(scaled(2.5));
		scale = 2.0;
		Sys.println(scaled(2.5));

		// Several returns from control flow.
		final pick = function(flag:Bool):Float {
			if (flag)
				return 1.75;
			return -0.5;
		};
		Sys.println(pick(true));
		Sys.println(pick(false));

		// Int results widen to the declared Float result, in block and expression bodies.
		var count = 3;
		final widened = function(flag:Bool):Float {
			if (flag)
				return 1;
			return count;
		};
		final expressionWidened = function():Float return count;
		Sys.println(widened(true) * 0.25);
		Sys.println(widened(false) * 0.25);
		Sys.println(expressionWidened() / 4);

		// Arithmetic and comparisons directly on Float call results.
		final a = function():Float return 1.25;
		final b = function():Float {
			return 0.5;
		};
		Sys.println(a() + 0.5);
		Sys.println(0.5 + a());
		Sys.println(a() + b());
		Sys.println(a() * a());
		Sys.println(a() / b() + 0.25);
		Sys.println(a() - 0.5);
		Sys.println(a() + 1);
		Sys.println(a() - 0.5 < a());
		final sum = a() + b();
		Sys.println(sum * 0.5);

		// A closure that adds the results of another closure.
		final outer = function(x:Float):Float {
			final inner = function(y:Float):Float {
				if (y > 1)
					return y + 0.25;
				return 0.75;
			};
			return inner(x) + inner(0.5);
		};
		Sys.println(outer(2.5));

		// Special values reach the caller unchanged.
		final negativeZero = function():Float {
			return -0.0;
		};
		final notANumber = function():Float {
			return Math.NaN;
		};
		Sys.println(1 / negativeZero() < 0);
		Sys.println(Math.isNaN(notANumber()));

		// Int-returning closures keep Int arithmetic; a String operand concatenates.
		final h = function():Int {
			return 2;
		};
		Sys.println(h() * h() + 1);
		Sys.println("sum=" + (a() + 0.5));
		Sys.println(a() + "!");
	}
}
