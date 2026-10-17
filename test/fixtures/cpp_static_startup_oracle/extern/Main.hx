class Main {
	static function main():Void {
		Sys.println(External.marker());
		Sys.println(Ordinary.marker());
		Sys.println("main");
	}
}

extern class External {
	public static inline function marker():String
		return "external";
	static function __init__():Void {
		Sys.println("extern-startup");
	}
}

class Ordinary {
	public static inline function marker():String
		return "ordinary";

	static function __init__():Void {
		Sys.println("ordinary-startup");
	}
}
