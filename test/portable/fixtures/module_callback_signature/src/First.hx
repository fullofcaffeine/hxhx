/** Exports precise callback types through a recursive module group. */
class First {
	public static function run(callback:Int->String, value:Int):String {
		return Second.run(callback, value);
	}

	public static function apply(callback:Int->String, value:Int):String {
		return callback(value);
	}

	public static function empty(callback:() -> String):String {
		return Second.empty(callback);
	}

	public static function invokeEmpty(callback:() -> String):String {
		return callback();
	}

	public static function retain(callback:Int->String):Int->String {
		return Second.retain(callback);
	}

	public static function identity(callback:Int->String):Int->String {
		return callback;
	}

	public static function pair(callback:(Int, String) -> String):String {
		return Second.pair(callback);
	}

	public static function invokePair(callback:(Int, String) -> String):String {
		return callback(7, "pair");
	}

	public static function optional(callback:(?value:String) -> String):String {
		return Second.optional(callback);
	}

	public static function invokeOptional(callback:(?value:String) -> String):String {
		return callback();
	}
}
