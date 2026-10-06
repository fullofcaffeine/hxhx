/** Array string conversion remains a separate required regression. */
class ArrayMain {
	static function values():Array<Bool> {
		Sys.println("array-effect");
		return [false, true];
	}

	static function text(value:Null<Array<Int>>):String {
		return Std.string(value);
	}

	static function element(value:Int):Int {
		Sys.println(value);
		return value;
	}

	static function main():Void {
		Sys.println(Std.string([1, 2]));
		final flags = [true, false];
		final alias = flags;
		Sys.println(Std.string(alias));
		Sys.println(Std.string(values()));
		Sys.println(text(null));
		Sys.println(text([0, 1]));
		final empty:Array<Int> = [];
		Sys.println(Std.string(empty));
		Sys.println(Std.string([[false], [true, false]]));
		Sys.println(Std.string(["left", "right"]));
		Sys.println(Std.string([element(3), element(4)]));
		final __hx_array_element_0 = 7;
		Sys.println(Std.string([__hx_array_element_0, element(8)]));
	}
}
