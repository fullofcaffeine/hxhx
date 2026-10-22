/** Finite conversions preserve the input and evaluate each authored operand once. */
class Main {
	static var effects:Int = 0;

	static function convert(value:Float):Int
		return Std.int(value);

	/** This standard API accepts numeric values hidden behind the language's Dynamic boundary. */
	static function recover(value:Dynamic):Int
		return Std.int(value);

	static function operand():Float {
		effects++;
		return -17.875;
	}

	static function main():Void {
		Sys.println(convert(0.0));
		Sys.println(convert(-0.0));
		Sys.println(convert(17.875));
		Sys.println(convert(-17.875));
		Sys.println(convert(0.75));
		Sys.println(convert(-0.75));
		Sys.println(convert(2147483647.0));
		Sys.println(convert(-2147483648.0));
		Sys.println(convert(2147483646.875));
		Sys.println(convert(-2147483647.875));
		Sys.println(recover(42));
		Sys.println(recover(-42));
		Sys.println(recover(2147483647));
		Sys.println(recover(-2147483647 - 1));
		Sys.println(recover(17.875));
		Sys.println(recover(-17.875));
		Sys.println(recover(0.0));
		Sys.println(recover(-0.0));
		Sys.println(recover(0.75));
		Sys.println(recover(-0.75));
		Sys.println(recover(2147483647.0));
		Sys.println(recover(-2147483648.0));
		Sys.println(recover(2147483646.875));
		Sys.println(recover(-2147483647.875));
		final value = operand();
		Sys.println(Std.int(value));
		Sys.println(Std.string(value));
		Std.int(operand());
		Sys.println(effects);
		Sys.println(Std.int(Std.int(operand())));
		Sys.println(effects);
	}
}
