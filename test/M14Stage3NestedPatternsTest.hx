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
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
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

	static function main():Void {
		checkUnprovenCoverage();
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = Path.join([root, "Main.hx"]);
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-nested-patterns", true);
		observe(executable, []);
		Sys.println("M14_STAGE3_NESTED_PATTERNS:PASS");
	}
}
