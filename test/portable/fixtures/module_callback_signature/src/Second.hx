/** Calls back into First so callback declarations must survive module assembly. */
class Second {
	public static function run(callback:Int->String, value:Int):String {
		return First.apply(callback, value);
	}

	public static function empty(callback:() -> String):String {
		return First.invokeEmpty(callback);
	}

	public static function retain(callback:Int->String):Int->String {
		return First.identity(callback);
	}

	public static function pair(callback:(Int, String) -> String):String {
		return First.invokePair(callback);
	}

	public static function optional(callback:(?value:String) -> String):String {
		return First.invokeOptional(callback);
	}
}
