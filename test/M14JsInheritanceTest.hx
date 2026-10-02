import sys.io.File;
import sys.FileSystem;
import backend.BackendContext;
import backend.js.JsBackend;

/** Compare real JavaScript inheritance effects with an independent upstream expectation. */
class M14JsInheritanceTest {
	/** Incomplete or ambiguous inheritance must fail before the renderer can invent a parent reference. */
	static function checkRejectedGraphs():Void {
		function reject(sources:Array<{name:String, source:String}>, expected:String):Void {
			final resolved = [
				for (entry in sources)
					new ResolvedModule(entry.name, entry.name + ".hx", ParserStage.parse(entry.source, entry.name + ".hx"))
			];
			final index = TyperIndex.build(resolved);
			final program = new MacroExpandedProgram([for (module in resolved) TyperStage.typeResolvedModule(module, index)], false);
			var rejected = false;
			try {
				new backend.js.JsClassInheritancePlan(program);
			} catch (error:String) {
				if (!StringTools.startsWith(error, expected))
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "invalid JavaScript inheritance graph was accepted: " + expected;
		}
		reject([
			{name: "Cycle", source: "class Cycle extends Parent {} class Parent extends Cycle {}"}
		], "JavaScript superclass cycle");
		reject([{name: "Missing", source: "class Missing extends Absent {}"}], "JavaScript superclass is unresolved");
		reject([
			{name: "One", source: "class One {} class Shared {}"},
			{name: "Two", source: "class Two {} class Shared {}"}
		], "JavaScript presentation name collides");
	}

	static function main():Void {
		checkRejectedGraphs();
		final root = "test/fixtures/js_inheritance";
		final expected = File.getContent(root + "/expected.stdout");
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "upstream inheritance contract differs: " + stdout + stderr;
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final output = ".tmp/js_inheritance_" + Std.string(Date.now().getTime());
		FileSystem.createDirectory(output);
		final script = output + "/main.js";
		new JsBackend().emit(MacroStage.expandProgram([typed], []),
			new BackendContext(output, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-classic=1"])));
		// This target observer checks native prototype identity after the Haxe program
		// runs. It does not supply compiler facts or modify the generated program.
		final observer = output + "/observer.js";
		File.saveContent(observer,
			File.getContent(script) + "\nif (__hx_cls_Main.created.__class__ !== __hx_cls_Child) throw new Error('child class identity lost');\n" +
			"if (Object.getPrototypeOf(__hx_cls_Child.prototype) !== __hx_cls_Parent.prototype) throw new Error('parent prototype lost');\n");
		final node = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node", observer]);
		final actual = node.stdout.readAll().toString();
		final errors = node.stderr.readAll().toString();
		final status = node.exitCode();
		node.close();
		if (status != 0 || actual != expected)
			throw "native inheritance observer failed; retained " + output + ": " + actual + errors;
		FileSystem.deleteFile(observer);
		FileSystem.deleteFile(script);
		FileSystem.deleteFile(script + ".map");
		FileSystem.deleteDirectory(output);
		Sys.println("JS_INHERITANCE_RUNTIME:PASS");
	}
}
