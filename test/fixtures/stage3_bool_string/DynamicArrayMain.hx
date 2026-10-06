/** Dynamic conversion must preserve array contents and Boolean identity. */
class DynamicArrayMain {
	static function text(value:Dynamic):String {
		return Std.string(value);
	}

	static function main():Void {
		final values:Array<Dynamic> = [false, 0, null, "tail"];
		Sys.println(Std.string(values));
		final uniform:Array<Dynamic> = [false, true];
		Sys.println(Std.string(uniform));
		Sys.println(text(values));
		final flags = [true, false];
		Sys.println(text(flags));
		Sys.println(text([1, 2]));
	}
}
