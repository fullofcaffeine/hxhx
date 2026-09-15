import backend.BackendContext;
import backend.vm.NekoTargetCore;
import sys.FileSystem;
import sys.io.File;

/** Runs stack primitives and similarly named user calls in both Neko output layouts. */
class M14NekoStackPrimitivesIntegrationTest {
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

	static function main():Void {
		for (name in ["__dollar__callstack", "__dollar__excstack", "__dollar__asize"]) {
			var rejected = false;
			try {
				backend.vm.NekoStackPrimitives.renderCall(EIdent(name), ["first", "second"]);
			} catch (error:String) {
				rejected = error.indexOf("requires") >= 0;
			}
			if (!rejected)
				throw "invalid primitive argument count was accepted: " + name;
		}
		if (backend.vm.NekoStackPrimitives.renderCall(EField(EIdent("user"), "__dollar__callstack"), []) != null
			|| backend.vm.NekoStackPrimitives.renderCall(EIdent("__dollar__callstack_extra"), []) != null)
			throw "primitive matching captured an ordinary call";
		final source = [
			"class Box {",
			"  public var value:Int;",
			"  public function new(value:Int) { this.value = value; }",
			"  public function next():Box return new Box(value + 1);",
			"}",
			"class Walk {",
			"  public static function first(n:Int):Int return n == 0 ? 11 : second(n - 1);",
			"  static function second(n:Int):Int return first(n);",
			"}",
			"class Probe {",
			"  public static function depth():Int return untyped __dollar__asize(__dollar__callstack());",
			"  public static function directDepth():Int return untyped $asize($callstack());",
			"  /** Native VM array stays at this boundary and is consumed immediately by asize. */",
			'  static function observedStack():Dynamic { Sys.println("stack-once"); return untyped __dollar__callstack(); }',
			"  public static function observedDepth():Int return untyped __dollar__asize(observedStack());",
			"  public static function caught():Bool {",
			'    try { throw "probe"; } catch (error:Dynamic) { return untyped __dollar__asize(__dollar__excstack()) > 0; }',
			"  }",
			"}",
			"class Main {",
			"  static function __dollar__callstack():Int return 37;",
			"  static function main():Void {",
			"    Sys.println(Probe.depth() > 0);",
			"    Sys.println(Probe.caught());",
			"    Sys.println(__dollar__callstack());",
			"    Sys.println(Main.__dollar__callstack());",
			"    var __dollar__excstack = function():Int return 41;",
			"    Sys.println(untyped __dollar__asize(__dollar__excstack()) >= 0);",
			"    Sys.println(Walk.first(3));",
			"    Sys.println(new Box(4).next().value);",
			"    Sys.println(Probe.directDepth() > 0);",
			"    Sys.println(Probe.observedDepth() > 0);",
			"  }",
			"}",
		].join("\n");
		final directory = ".tmp/m14_neko_stack_" + Std.string(Date.now().getTime());
		FileSystem.createDirectory(directory);
		File.saveContent(directory + "/Main.hx", source);
		final expected = "true\ntrue\n37\n37\ntrue\n11\n5\ntrue\nstack-once\ntrue\n";
		run("haxe", ["-cp", directory, "-main", "Main", "-neko", directory + "/upstream.n"]);
		if (run("neko", [directory + "/upstream.n"]) != expected)
			throw "upstream stack contract differs";
		final program = MacroStage.expandProgram([TyperStage.typeModule(ParserStage.parse(source, "Main.hx"))], []);
		final context = new BackendContext(directory, directory + "/main.n", "Main", true, false, new haxe.ds.StringMap<String>());
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, directory + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		final single = @:privateAccess NekoTargetCore.renderProgram(program, context);
		if (single.indexOf(".__hxhx_new_Box = function(value)") < 0)
			throw "single-file constructor changed its fixed argument convention";
		final supportSource = [for (part in split.support) part.source].join("\n");
		if (supportSource.indexOf(".__hxhx_new_Box = $varargs(function(__hxhx_args)") < 0)
			throw "split constructor changed its packed argument convention";
		File.saveContent(directory + "/single.neko", single);
		for (file in FileSystem.readDirectory(directory))
			if (StringTools.endsWith(file, ".neko"))
				run("nekoc", [directory + "/" + file]);
		for (layout in ["main", "single"])
			if (run("neko", [directory + "/" + layout + ".n"]) != expected)
				throw "native stack contract differs in " + layout + ": " + directory;
		Sys.println("NEKO_STACK_PRIMITIVES:PASS");
	}
}
