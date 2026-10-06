import sys.io.File;
import sys.FileSystem;

/** Upstream acceptance is the reference for writes through exact declared fields. */
class M14FieldAssignmentTest {
	static function main():Void {
		final cases:Array<{name:String, source:String, accepts:Bool}> = [
			{name: "bare_static", source: 'class Main {static var value=1;static function main():Void {value="bad";}}', accepts: false},
			{name: "qualified_static", source: 'class Main {static var value=1;static function main():Void {Main.value="bad";}}', accepts: false},
			{name: "bare_instance", source: 'class Main {var value=1;public function new() {value="bad";} static function main():Void {}}', accepts: false},
			{
				name: "this_instance",
				source: 'class Main {var value=1;public function new() {this.value="bad";} static function main():Void {}}',
				accepts: false
			},
			{
				name: "receiver",
				source: 'class Box {public var value=1;public function new() {}} class Main {static function main():Void {var b=new Box();b.value="bad";}}',
				accepts: false
			},
			{
				name: "generic_receiver",
				source: 'class Box<T> {public var value:T;public function new(value:T) {this.value=value;}} class Main {static function main():Void {var b=new Box<Int>(1);b.value="bad";}}',
				accepts: false
			},
			{
				name: "inherited",
				source: 'class Base {public var value=1;public function new() {}} class Main extends Base {public function new() {super();value="bad";} static function main():Void {}}',
				accepts: false
			},
			{name: "written", source: 'class Main {static var value:Int=1;static function main():Void {value="bad";}}', accepts: false},
			{
				name: "callback_result",
				source: 'class Main {static var callback=function():Int {return 1;};static function main():Void {callback=function():String {return "bad";};}}',
				accepts: false
			},
			{
				name: "callback_arity",
				source: 'class Main {static var callback=function(value:Int):Int {return value;};static function main():Void {callback=function():Int {return 1;};}}',
				accepts: false
			},
			{
				name: "nominal",
				source: 'class A {public function new() {}} class B {public function new() {}} class Main {static var value=new A();static function main():Void {value=new B();}}',
				accepts: false
			},
			{name: "record", source: 'class Main {static var value:{id:Int}={id:1};static function main():Void {value={id:"bad"};}}', accepts: false},
			{name: "valid", source: 'class Main {static var value=1;static function main():Void {value=2;}}', accepts: true},
			{name: "shadow", source: 'class Main {static var value=1;static function main():Void {var value="local";value="changed";}}', accepts: true},
			{name: "untyped_write", source: 'class Main {static var value=1;static function main():Void {untyped value="allowed";}}', accepts: true},
			{name: "untyped_value", source: 'class Main {static var value=1;static function main():Void {value=untyped "allowed";}}', accepts: true},
			{name: "nullable", source: 'class Main {static var value:Null<Int>=1;static function main():Void {value=null;}}', accepts: true},
			{name: "dynamic", source: 'class Main {static var value=1;static function main():Void {var input:Dynamic=2;value=input;}}', accepts: true},
			{
				name: "subtype",
				source: 'class Base {public function new() {}} class Child extends Base {public function new() {super();}} class Main {static var value=new Base();static function main():Void {value=new Child();}}',
				accepts: true
			},
			{
				name: "header_conversion",
				source: 'abstract Box(Int) from Int to Int {} class Main {static var value:Box=1;static function main():Void {value=2;}}',
				accepts: true
			},
			{
				name: "method_conversion",
				source: 'abstract Box(Int) {public function new(value:Int) {this=value;} @:from public static function wrap(value:Int):Box {return new Box(value+1);}} class Main {static var value:Box=new Box(1);static function main():Void {value=2;}}',
				accepts: true
			},
			{
				name: "callback_variance",
				source: 'class Main {static var value:Int->Void=function(value:Int):Void {};static function main():Void {value=function(value:Float):Int {return 1;};}}',
				accepts: true
			},
			{
				name: "callback_nominal_variance",
				source: 'class Base {public function new() {}} class Child extends Base {} class Main {static var callback:Child->Int;static function main():Void {callback=function(value:Base):Int {return 1;};}}',
				accepts: true
			},
			{
				name: "callback_nominal_narrowing",
				source: 'class Base {public function new() {}} class Child extends Base {} class Main {static var callback:Base->Int;static function main():Void {callback=function(value:Child):Int {return 1;};}}',
				accepts: false
			},
			{
				name: "nullable_header_conversion",
				source: 'abstract Box(Int) from Int to Int {} class Main {static var value:Null<Box>=null;static function main():Void {value=2;}}',
				accepts: true
			}
		];
		final root = ".tmp/field_assignment_contract";
		if (!FileSystem.exists(root))
			FileSystem.createDirectory(root);
		final failures = [];
		for (entry in cases) {
			final folder = root + "/" + entry.name;
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);
			File.saveContent(folder + "/Main.hx", entry.source);
			final upstream = new sys.io.Process("haxe", ["-cp", folder, "-main", "Main", "--no-output"]);
			final diagnostic = upstream.stderr.readAll().toString();
			final upstreamAccepted = upstream.exitCode() == 0;
			upstream.close();
			if (upstreamAccepted != entry.accepts)
				throw "upstream expectation differs: " + entry.name + " " + diagnostic;
			var accepted = true;
			var nativeDiagnostic = "";
			try {
				@:privateAccess M14DeclaredFieldTypesTest.typeSources([{name: "Main", source: entry.source}]);
			} catch (error:haxe.Exception) {
				accepted = false;
				nativeDiagnostic = error.message;
			}
			File.saveContent(folder
				+ "/diagnostics.txt",
				"upstream="
				+ upstreamAccepted
				+ "\n"
				+ diagnostic
				+ "native="
				+ accepted
				+ "\n"
				+ nativeDiagnostic
				+ "\n");
			if (accepted != entry.accepts)
				failures.push(entry.name + ": " + nativeDiagnostic);
			else
				Sys.println("FIELD_ASSIGNMENT:PASS " + entry.name);
		}
		if (failures.length > 0)
			throw "field assignment disagreements: " + failures.join("; ");
	}
}
