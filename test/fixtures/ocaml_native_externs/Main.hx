typedef Text = HostString;

@:native("HxString")
extern class HostString {
	@:native("length") public static function count(value:String):Int;
	public static function charAt(value:String, index:Int):String;
	public static function split(value:String, delimiter:String):Array<String>;
}

@:native("HxSys")
extern class HostSys {
	public static function systemName():String;
}

@:native("Stdlib.String")
extern class Nested {
	public static function length(value:String):Int;
}

@:native("HxBacktrace")
extern class HostStack {
	public static function callstack_lines(depth:Int):Array<String>;
	public static function exceptionstack_lines():Array<String>;
}

/** Exercise native exports through exact declarations, aliases, and saved values. */
class Main {
	static var initialized:Int = Text.count("ready");

	static function text():String {
		Sys.println("text");
		return "abc";
	}

	static function index():Int {
		Sys.println("index");
		return 1;
	}

	static function main():Void {
		Sys.println(initialized);
		Sys.println(Text.count("abc"));
		final count = Text.count;
		Sys.println(count("abcdef"));
		Sys.println((Text.count)("xy"));
		Sys.println(Text.charAt(text(), index()));
		final parts = Text.split("a,b", ",");
		Sys.println(parts.length);
		Sys.println(parts[1]);
		final system = HostSys.systemName;
		Sys.println(system().length > 0);
		Sys.println(HostSys.systemName().length > 0);
		Sys.println(Nested.length("four"));
		Sys.println(HostStack.callstack_lines(4).length >= 0);
		Sys.println(HostStack.exceptionstack_lines().length >= 0);
	}
}
