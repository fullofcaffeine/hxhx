/** Explicit untyped wrappers preserve the exact destination and evaluate its address once. */
class M14NekoUntypedAssignmentTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("untyped_assignment", 'class Box {public var value=2;public function new() {}}
class Main {
static var value=1;static var calls=0;static var rhsCalls=0;
static function receiver(box:Box):Box {calls++;return box;}
static function rhs():Int {rhsCalls++;return 7;}
static function main():Void {
untyped Main.value=3;
var box=new Box();untyped receiver(box).value=rhs();
Sys.println(value);Sys.println(box.value);Sys.println(calls);Sys.println(rhsCalls);
var values=[0];untyped values[0]=5;Sys.println(values[0]);
var local=0;untyped local=6;Sys.println(local);
var write=function():Void {untyped local=local+1;};write();Sys.println(local);
}}', "3\n7\n1\n1\n5\n6\n7\n");
	}
}
