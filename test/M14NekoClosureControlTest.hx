import backend.BackendContext;
import backend.vm.NekoTargetCore;
import sys.io.File;
import sys.FileSystem;

/** Closures own their returns and loop exits while retaining captured locals. */
class M14NekoClosureControlTest {
	static function main():Void {
		final source = 'class Counter {
public var read:Void->Int;
public function new(value:Int) { read = function():Int { value = value + 1; return value; }; }
}
class Main {
static function factory(value:Int):Void->Int {
return function():Int { value = value + 1; return value; };
}
static function pair(value:Int):{read:Void->Int, write:Void->Void} {
return {read:function():Int { return value; }, write:function():Void { value = value + 3; }};
}
static function nested(value:Int):Void->(Void->Int) {
return function():Void->Int { return function():Int { value = value + 2; return value; }; };
}
static function main():Void {
var count = 0;
var callback = function(value:Int):Int {
count = count + 1;
if (value < 0) return 7;
var nested = function(value:Int):Int { if (value == 0) return 11; return value + 2; };
var total = 0;
var index = 0;
while (index < value) {
index = index + 1;
if (index == 2) continue;
if (index == 4) break;
total = total + index;
}
return nested(0) + total;
};
Sys.println(callback(-1));
Sys.println(callback(5));
Sys.println(count);
Sys.println("outer");
var first = factory(10);
var second = factory(20);
Sys.println(first());
Sys.println(first());
Sys.println(second());
var shared = pair(30);
shared.write();
Sys.println(shared.read());
var outer = nested(40);
var inner = outer();
Sys.println(inner());
Sys.println(inner());
var value = 50;
var outside = function():Int { return value; };
{
var value = 60;
var inside = function():Int { value = value + 1; return value; };
Sys.println(inside());
}
Sys.println(outside());
var loopFirst:Void->Int = function():Int { return -1; };
var loopSecond:Void->Int = function():Int { return -1; };
for (item in [1,2]) {
var read = function():Int { return item; };
if (item == 1) loopFirst = read; else loopSecond = read;
}
Sys.println(loopFirst());
Sys.println(loopSecond());
var counter = new Counter(70);
Sys.println(counter.read());
Sys.println(counter.read());
function recurse(value:Int):Int { return value == 0 ? 3 : recurse(value - 1); }
Sys.println(recurse(2));
}
}';
		final expected = "7\n15\n2\nouter\n11\n12\n21\n33\n42\n44\n61\n50\n1\n2\n71\n72\n3\n";
		assertSource("boundaries", source, expected);
		final sequencing = "test/oracle/sequencing_local_seed/";
		assertSource("sequencing", File.getContent(sequencing + "src/Main.hx"), File.getContent(sequencing + "expected.stdout"));
		assertSource("catch", 'class Main { static function main():Void {
var read:Void->Int = function():Int { return -1; };
var write:Void->Void = function():Void {};
try { throw 8; } catch (value:Dynamic) {
read = function():Int { return value; };
write = function():Void { value = value + 1; };
}
write(); Sys.println(read()); write(); Sys.println(read());
} }', "9\n10\n");
		assertSource("lowered_catch", 'class Main {static function main():Void {
var make = function():Void->Int {try {throw 20;} catch(value:Dynamic) {return function():Int {value=value+1;return value;};}};
var next=make(); Sys.println(next()); Sys.println(next());
var nested = function():Int {try {try {throw 30;} catch(inner:Dynamic) {throw inner+1;}} catch(outer:Dynamic) {return outer+1;}};
Sys.println(nested());
}}', "21\n22\n32\n");
		assertSource("pattern", 'class Main { static function main():Void {
var read:Void->Int = function():Int { return -1; };
var write:Void->Void = function():Void {};
switch ({value:12}) { case {value:captured}:
read = function():Int { return captured; };
write = function():Void { captured = captured + 1; };
}
write(); Sys.println(read()); write(); Sys.println(read());
} }', "13\n14\n");
		assertSource("whole_pattern", 'class Main { static function main():Void {
var read:Void->Int = function():Int { return -1; };
switch (20) { case captured: read = function():Int { captured = captured + 1; return captured; }; }
Sys.println(read()); Sys.println(read());
} }', "21\n22\n");
	}

	/** Observe each authored contract upstream and in both generated layouts. */
	static function assertSource(name:String, source:String, expected:String):Void {
		final root = ".tmp/neko_closure_control_" + name + "_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		run("haxe", ["-cp", root, "-main", "Main", "-neko", root + "/upstream.n"]);
		if (run("neko", [root + "/upstream.n"]) != expected)
			throw "upstream closure control differs";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final defines = HxDefineMap.fromRawDefines(["neko=1"]);
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader([root], defines, index);
		loader.markResolvedAlready([resolved]);
		final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index, loader)], []);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(root + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, ".neko"))
				run("nekoc", [root + "/" + file]);
		for (layout in ["main", "single"]) {
			final actual = run("neko", [root + "/" + layout + ".n"]);
			File.saveContent(root + "/" + layout + ".stdout", actual);
			if (actual != expected)
				throw "closure control differs in " + layout + ": " + root;
			Sys.println("NEKO_CLOSURE_CONTROL:PASS fixture=" + name + " layout=" + layout);
		}
	}

	/** Require process success as well as output, including native compilation errors. */
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + errors;
		return output;
	}
}
