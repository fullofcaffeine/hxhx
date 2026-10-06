/** Runtime type bindings can change explicitly; existing objects keep their class identity. */
class M14NekoRuntimeTypeWriteTest {
	/** Real standard providers own predicates and startup; do not replace them with fixture shells. */
	static function assertSource(name:String, source:String, expected:String):Void {
		final folder = ".tmp/neko_runtime_type_write_source/" + name;
		sys.FileSystem.createDirectory(folder);
		sys.io.File.saveContent(folder + "/Main.hx", source);
		sys.io.File.saveContent(folder + "/expected.stdout", expected);
		NekoRuntimeFixture.exercise(folder, false, true);
	}

	static function main():Void {
		assertSource("runtime_type_write_primitive", 'class Main {
static var calls=0;
static function replacement():Dynamic {calls++;return {marker:7};}
static function main():Void {
var old=Int;var result=untyped (Int=replacement());
Sys.println((cast Int:Dynamic)==result);Sys.println(calls);
Sys.println((cast old:Dynamic)==(cast Int:Dynamic));
Sys.println(Std.isOfType(1,Int));Sys.println(Std.isOfType(1,old));
untyped Int=null;Sys.println(Std.isOfType(1,Int));
untyped Int=7;Sys.println(Std.isOfType(1,Int));
untyped Int=String;Sys.println(Std.isOfType(1,Int));Sys.println(Std.isOfType("x",Int));
untyped Int=old;Sys.println(Std.isOfType(1,old));
}}', "true\n1\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\n");
		assertSource("runtime_type_write_class", 'class Item {public function new(){} public function value():Int{return 1;}}
class Other {public function new(){} public function value():Int{return 2;}}
class Main {static function main():Void {
var old=Item;var original=new Item();var replacement:Dynamic={};untyped Item=replacement;
Sys.println((cast Item:Dynamic)==replacement);Sys.println(Type.getClass(original)==old);
Sys.println(Std.isOfType(original,old));Sys.println(Std.isOfType(original,Item));
try {var invalid=new Item();Sys.println("wrong");}catch(error:Dynamic){Sys.println("invalid constructor");}
untyped Item=Other;var changed=new Item();Sys.println(changed.value());
// Rebinding deliberately crosses unrelated class types; compare runtime identity at that boundary.
Sys.println((cast Type.getClass(changed):Dynamic)==(cast Other:Dynamic));
untyped Item=old;Sys.println(new Item().value());
}}', "true\ntrue\ntrue\nfalse\ninvalid constructor\n2\ntrue\n1\n");
		assertSource("runtime_type_write_shadow", 'class Main {static function main():Void {var Int=1;Int=2;Sys.println(Int);}}', "2\n");
	}
}
