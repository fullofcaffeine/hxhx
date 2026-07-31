class Unsupported {
	static function incompatibleFamily(mode:Int, value:Null<Int>):Null<Int> {
		final dynamicValue:Dynamic = "not-an-int";
		if (mode == 0)
			return 7;
		if (mode == 1)
			return dynamicValue;
		return value;
	}

	static function main():Void {
		Sys.println(Std.string(incompatibleFamily(0, null)));
	}
}
