/** Exact constructor selection preserves generic arguments, aliases, field initialization, and argument effects on Neko. */
class M14NekoGenericConstructionTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("generic_construction", 'class Box<T>{
public var value:T;
public var stamp:Int=Main.mark("field");
public function new(value:T){Main.mark("ctor");this.value=value;}
}
typedef Alias<T> = Box<T>;
class Main {
public static var events:String="";
static var seeded:Box<Int>=new Box<Int>(3);
public static function mark(event:String):Int {events+=event+";";return 7;}
static function argument(value:Int):Int {events+="arg;";return value;}
static function main():Void {
Sys.println(seeded.value);Sys.println(events);events="";
var first=new Box<Int>(argument(2));
var second=new Box(argument(4));
var third:Alias<Int>=new Alias<Int>(argument(6));
var record={box:new Box<Int>(argument(8))};
Sys.println(first.value);Sys.println(second.value);Sys.println(third.value);Sys.println(record.box.value);
Sys.println(first.stamp);Sys.println(events);
}
}',
			"3\nfield;ctor;\n2\n4\n6\n8\n7\narg;field;ctor;arg;field;ctor;arg;field;ctor;arg;field;ctor;\n");
	}
}
