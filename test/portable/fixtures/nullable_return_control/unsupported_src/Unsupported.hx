class Unsupported {
	static function nestedPrimitive(stop:Bool, value:Null<Int>):Null<Int> {
		if (stop)
			return 7;
		return value;
	}

	static function main():Void {
		Sys.println(Std.string(nestedPrimitive(true, null)));
	}
}
