import sys.io.File;

/** Null protection belongs to the compatible remaining cases, including nested accesses. */
class M14Stage3PatternNullTest {
	static final root = "test/fixtures/stage3_pattern_null";

	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (command != "haxe")
			File.saveContent(".tmp/stage3-pattern-null/observed.stdout", stdout);
		if (code != 0 || stdout != File.getContent(root + "/expected.stdout"))
			throw "Pattern null observer failed: " + command + ": " + stdout + stderr;
	}

	static function typed(source:String, path:String):TypedModule {
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	/** Unsupported guard syntax must not be mistaken for an unconditional pattern. */
	static function checkGuardDiagnostic():Void {
		final module = typed('class Main { static function main():Void { switch [1] { case [1] if (false): Sys.println("bad"); case _: Sys.println("ok"); } } }',
			"Main.hx");
		var rejected = false;
		try {
			EmitterStage.emitToDir(new MacroExpandedProgram([module], false), ".tmp/stage3-pattern-null-guard", true);
		} catch (error:String) {
			if (error.indexOf("requires executable guard or extractor lowering") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "Unsupported guard was silently discarded";
	}

	static function main():Void {
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = root + "/Main.hx";
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed(File.getContent(path), path)], false), ".tmp/stage3-pattern-null", true);
		observe(executable, []);
		checkGuardDiagnostic();
		Sys.println("M14_STAGE3_PATTERN_NULL:PASS");
	}
}
