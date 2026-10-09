/** Exact static storage must preserve declaring owners independently of startup initialization. */
class M14NekoStaticFieldTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("static_inferred_field", 'class Payload {
public static var stringCalls=0;
public function new() {}
public function toString():String {stringCalls++;return "payload";}
} class Main {static function main():Void {var value=new Payload();Sys.println(Payload.stringCalls);Sys.println(value.toString());Sys.println(Payload.stringCalls);}}',
			"0\npayload\n1\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("inferred_instance_callable", 'class Payload {
public var value=3;
public var callback=function(value:Int):Int {return value+2;};
public function new() {}
public function read():Int {return value;}
}
typedef Alias=Payload;
class Main {static function main():Void {var a=new Alias();var b=new Payload();a.value++;Sys.println(a.read());Sys.println(b.read());Sys.println(a.callback(5));}}',
			"4\n3\n7\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("static_field_owner", 'class Base {
public static var count:Int;
public static function bump():Int {count=count+1; return count;}
}
typedef Alias=Base;
class Main {
static var count:Int;
static var callback:Void->Int;
static function bump():Int {count=count+2; return count;}
static function main():Void {
Main.count=10; Base.count=30;
Sys.println(bump()); Sys.println(Main.count);
Sys.println(Base.bump()); Sys.println(Base.count);
Base.count+=4; Sys.println(Base.count); Alias.count+=2; Sys.println(Base.count);
Sys.println(count++); Sys.println(++count);
var count=90; count++; Sys.println(count); Sys.println(Main.count);
callback=function():Int {return Main.count;}; Sys.println(callback()); Sys.println(Main.callback());
}
}', "12\n12\n31\n31\n35\n37\n12\n14\n91\n14\n14\n14\n");
	}
}
