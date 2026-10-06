/** Primitive values keep their identity when standard conversion receives Dynamic. */
class Main {
	static var evaluations:Int = 0;

	static function next():Int {
		evaluations++;
		return -7;
	}

	static function text(value:Dynamic):String {
		return Std.string(value);
	}

	static function main():Void {
		final absent:Null<Int> = null;
		Sys.println(text(next()));
		Sys.println(text(absent));
		Sys.println(text(true));
		Sys.println(text(false));
		Sys.println(text(0));
		Sys.println(text("héllo"));
		Sys.println(text(""));
		Sys.println(evaluations);
	}
}
