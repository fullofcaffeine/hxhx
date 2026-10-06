/** Independently ask upstream for integer arithmetic result types, before any target rendering. */
class TypeCheck {
	public static function verify():Void {
		for (op in ["+", "-", "*", "%"])
			for (operands in ["left " + op + " 2", "2 " + op + " left", "left " + op + " right"]) {
				final position = haxe.macro.Context.currentPos();
				final expression = haxe.macro.Context.parse("{var left:Null<Int>=7;var right:Null<Int>=3;" + operands + ";}", position);
				final actual = haxe.macro.TypeTools.toString(haxe.macro.Context.typeof(expression));
				if (actual != "Int")
					haxe.macro.Context.error(operands + " has unexpected type " + actual, position);
			}
		Sys.println("UPSTREAM_NULLABLE_INTEGER_RESULT:PASS");
	}
}
