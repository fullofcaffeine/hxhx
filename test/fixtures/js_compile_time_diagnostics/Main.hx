import HelperMacros.typeError;

/** The existing diagnostic adapter must type its source input before JavaScript emission. */
class Main {
	static function check(value:Bool, label:String):Void {
		if (!value)
			throw label;
	}

	static function main():Void {
		final message = HelperMacros.typeErrorText(for (key => value in 1) {});
		check(message == "Int has no field keyValueIterator", "integer iteration diagnostic");
		check(HelperMacros.typeError(for (key => value in new MyNotIterator()) {}), "missing iterator diagnostic");
		check(HelperMacros.typeError(for (key => value in 0...2) {}), "range entry diagnostic");
		check(!typeError({var b:{v:Dynamic} = {v: "foo"};}), "valid structural block");
		check(typeError({var b:{v:Int} = {v: 1.2};}), "invalid structural block");
		check(HelperMacros.typeErrorText(1 + 2) == null, "successful probe has no diagnostic");
		var unchanged = 7;
		check(!HelperMacros.typeError({var unchanged:String = "private";}), "private declaration is valid");
		check(unchanged == 7, "probe declarations do not escape");
	}
}

/** A declared class without an iteration protocol remains invalid as a loop source. */
class MyNotIterator {
	public function new() {}
}
