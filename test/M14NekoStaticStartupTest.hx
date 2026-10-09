/** Compare startup phases, dependencies, and loaded-class effects with upstream Neko. */
class M14NekoStaticStartupTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("static_startup_order", 'class Main {
static var own:Int=mark("Main.field",9);
static function __init__():Void {Sys.println("Main.__init__");}
public static function mark(label:String,value:Int):Int {Sys.println(label);return value;}
static function main():Void {Sys.println("main");Sys.println(Alpha.first);}
} class Alpha {
public static var first:Int=Main.mark("Alpha.first",1); public static var second:Int=Main.mark("Alpha.second",Beta.value);
static function __init__():Void {Sys.println("Alpha.__init__");}
} class Beta {public static var value:Int=Main.mark("Beta.value",2);static function __init__():Void {Sys.println("Beta.__init__");}}
class Unused {public static var value:Int=Main.mark("Unused.value",3);static function __init__():Void {Sys.println("Unused.__init__");}}',
			"Main.__init__\nBeta.__init__\nAlpha.__init__\nUnused.__init__\nMain.field\nBeta.value\nAlpha.first\nAlpha.second\nUnused.value\nmain\n1\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_startup_forward", 'class Main {
static var first:Int=mark("first",second);static var second:Int=mark("second",2);
static function mark(label:String,value:Int):Int {Sys.println(label);Sys.println(value);return value;}
static function main():Void {Sys.println(first);Sys.println(second);}}', "first\nnull\nsecond\n2\nnull\n2\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_startup_cycle", 'class Other {public static var value:Null<Int>=Main.value;}
class Main {public static var value:Null<Int>=Other.value;static function main():Void {Sys.println(value);Sys.println(Other.value);}}', "null\nnull\n");
		for (mode in ["none", "eager", "invoked", "stored", "dead"]) {
			final body = switch mode {
				case "eager": "return Gamma.value;";
				case "invoked": "final get=function():Int {return Gamma.value;};return get();";
				case "stored": "final get=function():Int {return Gamma.value;};return value;";
				case "dead": "if(false) return Gamma.value;return value;";
				case _: "return value;";
			};
			final source = 'class Main {public static function mark(label:String,value:Int):Int {Sys.println(label);return value;}static function main():Void {Sys.println(Alpha.value);}}
class Alpha {public static var value:Int=Main.mark("Alpha",Beta.read());}
class Beta {public static var value:Int=Main.mark("Beta",2);public static var later:Void->Int=function():Int {return Gamma.value;};public static function read():Int {'
				+ body
				+ '}}
class Gamma {public static var value:Int=Main.mark("Gamma",3);}';
			final expected = mode == "none" ? "Beta\nAlpha\nGamma\n2\n" : "Beta\nGamma\nAlpha\n" + (mode == "eager" || mode == "invoked" ? "3\n" : "2\n");
			@:privateAccess M14NekoClosureControlTest.assertSource("static_startup_" + mode, source, expected);
		}
	}
}
