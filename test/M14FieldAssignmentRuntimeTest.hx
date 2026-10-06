/** Accepted field writes retain storage, receiver substitution, and conversion effects at runtime. */
class M14FieldAssignmentRuntimeTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("field_assignment_runtime",
			'class Box<T> {public var value:T;public function new(value:T) {this.value=value;}}
class Main {
static var count=1;
var value=2;
public function new() {}
static var callback=function(value:Int):Int {return value;};
static function main():Void {
var a=new Main();var b=new Main();var box=new Box<Int>(3);
count=4;a.value=5;box.value=6;callback=function(value:Int):Int {return value+1;};
Sys.println(count);Sys.println(a.value);Sys.println(b.value);Sys.println(box.value);Sys.println(callback(6));
}}', "4\n5\n2\n6\n7\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("field_assignment_conversion", 'abstract Wrapped(Int) {
@:from public static function wrap(value:Int):Wrapped {Main.calls++;return cast (value+10);}
public function read():Int {return this;}
}
class Main {
public static var calls=0;
static var value:Wrapped=cast 1;
static function main():Void {var observed=(value=2);Sys.println(observed.read());Sys.println(value.read());Sys.println(calls);}
}', "12\n12\n1\n");
	}
}
