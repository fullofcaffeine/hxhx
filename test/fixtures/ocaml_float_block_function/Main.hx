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
		final one:Float = widened(true);
		final three:Float = widened(false);
		Sys.println(one * 0.25);
		Sys.println(three * 0.25);
		final expressionWidened = function():Float return count;
		final threeAgain:Float = expressionWidened();
		Sys.println(threeAgain / 4);
	}
}
