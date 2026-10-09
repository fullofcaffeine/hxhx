/** Observe parameter ownership in helpers whose bodies retain their existing neutral behavior. */
class Main {
	static function main():Void {
		Sys.println(TypeTools.map(7, 9));
		Sys.println(TypeTools.findField(Probe.next(), "ignored"));
		Sys.println(MacroStringTools.isFormatExpr("first", "second"));
		Sys.println(Probe.evaluations);
		Sys.println(SysTools.quoteUnixArg("first path", "second path"));
		Sys.println(SysTools.quoteWinArg("win path"));
	}
}

/** These source bodies independently specify the helper behavior observed by the native test. */
class TypeTools {
	public static function map(int:Int, int_:Int):Int
		return int;

	public static function findField<A>(int:A, int_:String):Bool
		return false;
}

/** The two source names collide under simple C++ keyword sanitization. */
class MacroStringTools {
	public static function isFormatExpr(int:String, int_:String):Bool
		return false;
}

/** Count actual argument evaluations independently of the generated helper body. */
class Probe {
	public static var evaluations:Int = 0;

	public static function next():Int {
		evaluations++;
		return 3;
	}
}

/** A space requires quoting; the second generic argument must not replace the first. */
class SysTools {
	public static function quoteUnixArg<A>(int:String, int_:A):String
		return "'" + int + "'";

	public static function quoteWinArg(int:String, int_:Bool = false):String
		return '"' + int + '"';
}
