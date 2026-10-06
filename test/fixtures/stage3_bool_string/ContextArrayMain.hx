/** Every destination supplies its array element storage before Boolean identity is erased. */
class ContextArrayMain {
	static final initial:Array<Dynamic> = [false, true];

	static function make():Array<Dynamic> {
		return [false, true];
	}

	static function describe(values:Array<Dynamic>):String {
		return Std.string(values);
	}

	static function main():Void {
		var values:Array<Dynamic> = [false, true];
		Sys.println(Std.string(values));
		values = [true, false];
		Sys.println(Std.string(values));
		Sys.println(describe([false, true]));
		Sys.println(Std.string(make()));
		final nested:Array<Array<Dynamic>> = [[false], [true]];
		Sys.println(Std.string(nested));
		Sys.println(Std.string(initial));
	}
}
