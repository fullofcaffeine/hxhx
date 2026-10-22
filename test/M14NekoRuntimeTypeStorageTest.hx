/** Source-level storage and constructor effects are independent of standard-library startup. */
class M14NekoRuntimeTypeStorageTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("runtime_type_storage", 'class Main {
static var calls=0;
static function replacement():Dynamic {calls++;return {marker:7};}
static function main():Void {
var original=Int;var assigned=untyped (Int=replacement());
Sys.println((cast Int:Dynamic)==assigned);Sys.println(calls);Sys.println((cast Int:Dynamic)==(cast original:Dynamic));
untyped Int=null;Sys.println((cast Int:Dynamic)==null);
untyped Int=7;Sys.println((cast Int:Dynamic)==7);
untyped Int=original;Sys.println((cast Int:Dynamic)==(cast original:Dynamic));
var Int=1;Int=2;Sys.println(Int);
}}', "true\n1\nfalse\ntrue\ntrue\ntrue\n2\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("runtime_type_constructor_binding",
			'class Item {public function new(){} public function value():Int{return 1;}}
class Other {public function new(){} public function value():Int{return 2;}}
class Main {static function main():Void {
var original:Dynamic=Item;var before=new Item();untyped Item=Other;var after=new Item();
Sys.println(before.value());Sys.println(after.value());Sys.println((cast Item:Dynamic)==(cast Other:Dynamic));
untyped Item={};try {var invalid=new Item();Sys.println("wrong");}catch(error:Dynamic){Sys.println("invalid constructor");}
untyped Item=original;Sys.println(new Item().value());
}}', "1\n2\ntrue\ninvalid constructor\n1\n");
		for (entry in [
			{source: "class Main {static function main():Void {Int={};}}", accepts: false},
			{source: "class Item {} class Main {static function main():Void {Item={};}}", accepts: false},
			{source: "class Main {static function main():Void {untyped Int={};}}", accepts: true},
			{source: "class Main {static function main():Void {var Int=1;Int=2;}}", accepts: true}
		]) {
			final root = ".tmp/runtime_type_write_checking";
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + "/Main.hx", entry.source);
			final upstream = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--no-output"]);
			final diagnostic = upstream.stderr.readAll().toString();
			final upstreamAccepted = upstream.exitCode() == 0;
			upstream.close();
			if (upstreamAccepted != entry.accepts)
				throw "upstream runtime type write expectation differs: " + diagnostic;
			var accepted = true;
			try
				@:privateAccess M14DeclaredFieldTypesTest.typeSources([{name: "Main", source: entry.source}])
			catch (error:haxe.Exception) {
				accepted = false;
				if (error.message.indexOf("Invalid assign") < 0)
					throw error;
			}
			if (accepted != entry.accepts)
				throw "runtime type write checking differs: " + entry.source;
		}
		Sys.println("RUNTIME_TYPE_STORAGE_CHECKING:PASS");
	}
}
