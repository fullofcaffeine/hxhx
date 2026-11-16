import sys.FileSystem;

/**
	Builds a program whose locals are named `_` with the Stage3 native emitter
	and compares its output with upstream Haxe.

	Why
	- Haxe `_` is an ordinary local that can be read: `catch (_:String)
	  trace(_)` prints the caught value. OCaml `_` is a wildcard pattern that
	  cannot be read. Stage3 refused every such binding with
	  `cannot render exact binding ... :_`, so a program with
	  `catch (_:String)`, `for (_ in ...)`, `(_) -> 1`, `function(_:Int)`, or
	  `var _` did not build natively.

	What
	- `stage3_underscore_bindings` uses `_` as a catch variable (braced,
	  unbraced, read, and in two catches of one try), a loop variable (also
	  nested), lambda and function parameters (also twice in one lambda),
	  method parameters, an ordinary local, and a pattern wildcard.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3UnderscoreBindingsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function main():Void {
		final source = "test/fixtures/stage3_underscore_bindings";
		final path = source + "/Main.hx";
		final expected = sys.io.File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_underscore_bindings";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: sys.io.File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_UNDERSCORE_BINDINGS:PASS");
	}
}
