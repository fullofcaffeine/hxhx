/** Separate loaded classes from dependencies found inside a called initializer helper. */
class Main {
	public static function mark(text:String, value:Int):Int {
		Sys.println(text);
		return value;
	}

	static function main():Void {
		Sys.println(Alpha.value);
	}
}

class Alpha {
	public static var value:Int = Main.mark("Alpha", Beta.read());
}

class Beta {
	public static var value:Int = Main.mark("Beta", 2);

	public static function read():Int {
		#if eager
		return Gamma.value;
		#elseif stored
		final get = function() return Gamma.value;
		return value;
		#elseif dead
		if (false)
			return Gamma.value;
		return value;
		#elseif invoked
		final get = function() return Gamma.value;
		return get();
		#else
		return value;
		#end
	}

	public static function dormant():Int {
		return Gamma.value;
	}

	public static var later:Void->Int = function() return Gamma.value;
}

class Gamma {
	public static var value:Int = Main.mark("Gamma", 3);
}
