/** Exact callback boundaries preserve concrete arguments and evaluate factories once. */
class Main {
	static function applyOnce(callback:Int->Int):Int
		return callback(5);

	static function applyInt(callback:Int->Int):Int {
		Sys.println("applyInt");
		Sys.println(callback(5));
		return callback(6);
	}

	static function applyBool(callback:Bool->Bool):Bool
		return callback(false);

	static function applyString(callback:String->String):String
		return callback("text");

	static function applyVoid(callback:Int->Void):Void {
		callback(5);
	}

	static function observe(value:Dynamic):Dynamic {
		Sys.println(value);
		return value;
	}

	static function make():Dynamic->Dynamic {
		Sys.println("make");
		return (value:Dynamic) -> value;
	}

	static function main():Void {
		Sys.println(applyOnce((value:Int) -> value + 10));
		Sys.println(applyOnce(value -> value + 10));
		Sys.println(applyOnce((value:Dynamic) -> value + 10));
		Sys.println(applyInt(make()));
		Sys.println(applyBool(make()));
		Sys.println(applyString(make()));
		Sys.println(applyBool((value:Dynamic) -> !value));
		Sys.println(applyBool((value:Dynamic) -> value));
		Sys.println(applyString((value:Dynamic) -> value));
		applyVoid((value:Dynamic) -> observe(value));
	}
}
