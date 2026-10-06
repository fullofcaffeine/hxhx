/** Expose the order of class startup methods, field initializers, and the entry point. */
class Main {
	static var own:Int = mark("Main.field", 9);

	static function __init__():Void {
		say("Main.__init__");
	}

	public static function say(text:String):Void {
		#if js
		js.Syntax.code("console.log({0})", text);
		#else
		Sys.println(text);
		#end
	}

	public static function mark(text:String, value:Int):Int {
		say(text);
		return value;
	}

	static function main():Void {
		say("main");
		say(Std.string(Alpha.first));
	}
}

class Alpha {
	public static var first:Int = Main.mark("Alpha.first", 1);
	public static var second:Int = Main.mark("Alpha.second", Beta.value);

	static function __init__():Void {
		Main.say("Alpha.__init__");
	}
}

class Beta {
	public static var value:Int = Main.mark("Beta.value", 2);

	static function __init__():Void {
		Main.say("Beta.__init__");
	}
}

class Unused {
	public static var value:Int = Main.mark("Unused.value", 3);

	static function __init__():Void {
		Main.say("Unused.__init__");
	}
}
