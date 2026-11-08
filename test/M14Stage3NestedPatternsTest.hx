import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.io.File;

/** Compare native pattern selection with independently specified Haxe behavior. */
class M14Stage3NestedPatternsTest {
	static final root = "test/fixtures/stage3_nested_patterns";

	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (command != "haxe")
			File.saveContent(".tmp/stage3-nested-patterns/observed.stdout", stdout);
		if (code != 0 || stdout != File.getContent(Path.join([root, "expected.stdout"])))
			throw "Nested pattern observer failed for " + command + ": " + stdout + stderr;
	}

	/** Incomplete patterns and resolved constants must not authorize result storage. */
	static function checkUnprovenCoverage():Void {
		final cases = [
			{prefix: "", type: "Array<Int>", pattern: "[1]"},
			{prefix: "", type: "{flag:Bool}", pattern: "{flag:true}"},
			{prefix: "", type: "Bool", pattern: "x if(false)"},
			{prefix: "static final expected:Bool = true;", type: "Bool", pattern: "expected"}
		];
		for (entry in cases) {
			final source = "class Main { " + entry.prefix + " static function value(v:" + entry.type + "):Int return switch v {case " + entry.pattern
				+ ": 2;}; static function main():Void {} }";
			final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: "Main.hx", root: root});
			var rejected = false;
			try {
				typed.getBackendProjection();
			} catch (error:String) {
				if (error.indexOf("requires exact exhaustive coverage") < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "unproven switch coverage accepted: " + entry.pattern;
		}
	}

	/**
		Guards on enum, constant, array, and anonymous-structure patterns, including
		nested patterns, captured locals, and side-effect order. A false guard must
		fall through to the next matching case on upstream Haxe, native OCaml, and JS.
	 */
	static function checkCaseGuards():Void {
		final guardRoot = "test/fixtures/stage3_case_guards";
		final expected = File.getContent(Path.join([guardRoot, "expected.stdout"]));
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", guardRoot, "--run", "Main"], expected: expected});
		final path = Path.join([guardRoot, "Main.hx"]);
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: guardRoot});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-case-guards");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		final result = BackendRegistry.requireForTarget("js-native")
			.emit(MacroStage.expandProgram([typed], []),
				new BackendContext(".tmp/stage3-case-guards-js-native", null, "Main", false, new haxe.ds.StringMap<String>()));
		M14Stage3RuntimeFixture.observe({command: "node", arguments: [result.entryPath], expected: expected});
		Sys.println("M14_STAGE3_CASE_GUARDS:PASS");
	}

	static function main():Void {
		checkUnprovenCoverage();
		checkCaseGuards();
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = Path.join([root, "Main.hx"]);
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-nested-patterns");
		observe(executable, []);
		Sys.println("M14_STAGE3_NESTED_PATTERNS:PASS");
	}
}
