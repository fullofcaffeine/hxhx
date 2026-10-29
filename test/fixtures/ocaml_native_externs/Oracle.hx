/** Ordinary Haxe operations independently define the caller-visible native fixture results. */
class Oracle {
	static function text():String {
		Sys.println("text");
		return "abc";
	}

	static function index():Int {
		Sys.println("index");
		return 1;
	}

	static function main():Void {
		Sys.println("ready".length);
		Sys.println("abc".length);
		final count = value -> value.length;
		Sys.println(count("abcdef"));
		Sys.println("xy".length);
		Sys.println(text().charAt(index()));
		final parts = "a,b".split(",");
		Sys.println(parts.length);
		Sys.println(parts[1]);
		final system = Sys.systemName;
		Sys.println(system().length > 0);
		Sys.println(Sys.systemName().length > 0);
		Sys.println("four".length);
		Sys.println(haxe.CallStack.callStack().length >= 0);
		Sys.println(haxe.CallStack.exceptionStack().length >= 0);
	}
}
