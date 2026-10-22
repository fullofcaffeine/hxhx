/** Initializer blocks retain per-field and per-instance captured storage, and throws stop construction. */
class M14JsFieldInitializerControlTest {
	public static function run():Void {
		final source = '@:native("console") extern class Console {public static function log(value:String):Void;}
@:native("global") extern class Runtime {public static function gc():Void;}
class First {
public static var next:Void->Int={var value=10;function():Int{value=value+1;return value;};};
}
class Second {
public static var next:Void->Int={var value=20;function():Int{value=value+1;return value;};};
}
class Holder {
public var first:Void->Int={var value=30;function():Int{value=value+1;return value;};};
public var second:Void->Int={var value=40;function():Int{value=value+1;return value;};};
public function new(){}
}
class Broken {
public var value:Int={Console.log("before");throw "stop";};
public function new(){Console.log("unexpected constructor");}
}
class Main {
static var seed=50;
static var read:Void->Int={var value=seed;function():Int{value=value+1;return value;};};
static function print(value:Int):Void{Console.log(""+value);}
static function main():Void {
print(First.next());print(Second.next());print(First.next());print(read());
var first=new Holder();var second=new Holder();
Runtime.gc();
print(first.first());print(first.second());print(first.first());print(second.first());
try {var broken=new Broken();Console.log("unexpected completion");}catch(error:Dynamic){Console.log("caught");}
}}';
		final expected = "11\n21\n12\n51\n31\n41\n32\n31\nbefore\ncaught\n";
		final root = ".tmp/js-field-initializer-control";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = @:privateAccess M14JsPlainExternBindingTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		if (upstream.code != 0)
			throw "upstream initializer compilation failed: " + upstream.stderr;
		final observed = @:privateAccess M14JsPlainExternBindingTest.run("node", ["--expose-gc", root + "/upstream.js"]);
		if (observed.code != 0 || observed.stdout != expected)
			throw "upstream initializer execution differs: " + observed.stdout + observed.stderr;
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected, ["--expose-gc"]);
		Sys.println("JS_FIELD_INITIALIZER_CONTROL:PASS");
	}

	static function main():Void
		run();
}
