package providers;

/** A packaged static provider whose unused method must remain removable. */
class Api {
	public static function combine(left:String, right:String):String {
		return "provider:" + left + ":" + right;
	}

	public static function unused():String {
		return "must-stay-unused";
	}

	/** A later-declared partner must remain callable from a recursive cycle. */
	public static function repeat(count:Int):String {
		if (count <= 0)
			return "recursive";
		return next(count - 1);
	}

	static function next(count:Int):String {
		return repeat(count);
	}

	/** A local callable must not retain the unused static declaration with the same name. */
	public static function shadow():String {
		var unused = function():String return "local-function";
		return unused();
	}

	public static function decorate(value:String):String {
		return "extension:" + value;
	}

	/** A required nullable parameter still selects this declaration for a null literal. */
	public static function nullable(value:Null<String>):String {
		return value == null ? "nullable:null" : value;
	}
}
