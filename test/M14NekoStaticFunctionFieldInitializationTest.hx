/** A stored function literal is available before ordinary static field initializers run. */
class M14NekoStaticFunctionFieldInitializationTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("static_function_field", 'class Holder {
public static var first=make();
static var make:Void->Int=function(){return 7;};
}
class Main {static function main():Void {Sys.println(Holder.first);}}', "7\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_function_identity", 'class Holder {
public static var saved=make;
public static var changed=replace();
public static var make:Void->Int=function(){return 7;};
static function replace():Int {make=function(){return 9;};return make();}
}
class Main {static function main():Void {
Sys.println(Holder.saved());Sys.println(Holder.changed);Sys.println(Holder.make());Sys.println(Holder.saved==Holder.make);
}}', "7\n9\n9\nfalse\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_function_hook", 'class Holder {
public static var first=make();
public static var make:Void->Int=function(){return 3;};
static function __init__():Void {Sys.println(make());make=function(){return 5;};}
}
class Main {static function main():Void {Sys.println(Holder.first);Sys.println(Holder.make());}}', "3\n5\n5\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_function_factory", 'class Holder {
public static var first=attempt();
public static var make:Void->Int=create();
static function create():Void->Int {return function(){return 11;};}
static function attempt():Int {try {return make();} catch(error:Dynamic) {return -1;}}
}
class Main {static function main():Void {Sys.println(Holder.first);Sys.println(Holder.make());}}', "-1\n11\n");
	}
}
