/** Every branch of a conditional inside a case body must stay reachable. */
class Main {
	/** A local declaration followed by an expression `if` that yields the case value. */
	static function weekday(day:Int, code:String):String {
		final date:Dynamic = {getDay: () -> day};
		return switch code {
			case "u":
				var t = date.getDay();
				if (t == 0) "7" else Std.string(t);
			case "w":
				if (day == 0) "sunday" else if (day == 6) "saturday" else "weekday";
			default:
				"";
		};
	}

	/** A ternary is the expression form of the same choice. */
	static function ternary(value:Int):String {
		return switch value {
			case 0: "zero";
			case n: n > 0 ? "positive" : "negative";
		};
	}

	/** Nested conditionals choose an inner else that belongs to the inner `if`. */
	static function nested(value:Int, flag:Bool):String {
		return switch value {
			case 1:
				if (flag) if (value > 0)
					"flag-positive"
				else
					"flag-other" else "no-flag";
			case _:
				if (flag) {
					var label = "flag";
					label + "-default";
				} else {
					"default";
				}
		};
	}

	/** Statement cases accept a semicolon before `else`, like an ordinary block. */
	static function statement(value:Int):Void {
		switch value {
			case 1:
				if (value > 5)
					Sys.println("big");
				else
					Sys.println("small");
			case 2:
				if (value > 5) {
					Sys.println("big");
				} else if (value > 1) {
					Sys.println("medium");
				} else {
					Sys.println("small");
				}
			case _:
				if (value < 0)
					Sys.println("negative");
				Sys.println("after");
		}
	}

	/** The same conditional outside a switch keeps its else branch too. */
	static function block(day:Int):String {
		final result = {
			var t = day;
			if (t == 0)
				"7"
			else
				Std.string(t);
		};
		return result;
	}

	static function main():Void {
		Sys.println(weekday(0, "u"));
		Sys.println(weekday(3, "u"));
		Sys.println(weekday(0, "w"));
		Sys.println(weekday(6, "w"));
		Sys.println(weekday(2, "w"));
		Sys.println(weekday(2, "x"));
		Sys.println(ternary(0));
		Sys.println(ternary(4));
		Sys.println(ternary(-4));
		Sys.println(nested(1, true));
		Sys.println(nested(1, false));
		Sys.println(nested(2, true));
		Sys.println(nested(2, false));
		statement(1);
		statement(2);
		statement(-3);
		statement(9);
		Sys.println(block(0));
		Sys.println(block(5));
	}
}
