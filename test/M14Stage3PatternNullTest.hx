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
		return M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
	}

	/**
		A false guard on a structural pattern must fall through to the next case.
		Shared typed control lowering turns guards into ordinary conditions before
		OCaml pattern selection, so the program must run and print the later case.
	 */
	static function checkGuardFallthrough():Void {
		final module = typed('class Main { static function main():Void { switch [1] { case [1] if (false): Sys.println("bad"); case _: Sys.println("ok"); } } }',
			"Main.hx");
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([module], false), ".tmp/stage3-pattern-null-guard");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "ok\n"});
	}

	/**
		Patterns that Stage3 cannot execute yet must stop emission with a named
		error instead of being treated as an unconditional match. Extractors have
		no native lowering; a guard attached to one must not hide that either.
		A plain extractor reaches OCaml pattern selection. A guarded extractor is
		rejected earlier, by the shared guard planner, which cannot split it into
		a structural test.
	 */
	static function checkUnsupportedPatternDiagnostic():Void {
		final cases = [
			{pattern: "_.length => 2", diagnostic: "requires executable guard or extractor lowering"},
			{pattern: "_.length => n if (n > 0)", diagnostic: "guarded pattern requires a structural decision"}
		];
		for (entry in cases) {
			final module = typed('class Main { static function main():Void { switch [1] { case '
				+ entry.pattern
				+ ': Sys.println("bad"); case _: Sys.println("ok"); } } }',
				"Main.hx");
			var rejected = false;
			try {
				EmitterStage.emitToDir(new MacroExpandedProgram([module], false), ".tmp/stage3-pattern-null-extractor");
			} catch (error:String) {
				if (error.indexOf(entry.diagnostic) < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "Unsupported extractor pattern was silently discarded: " + entry.pattern;
		}
	}

	static function main():Void {
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = root + "/Main.hx";
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed(File.getContent(path), path)], false), ".tmp/stage3-pattern-null");
		observe(executable, []);
		checkGuardFallthrough();
		checkUnsupportedPatternDiagnostic();
		Sys.println("M14_STAGE3_PATTERN_NULL:PASS");
	}
}
