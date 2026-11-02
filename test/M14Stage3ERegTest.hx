import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a regular-expression program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- On the OCaml target, `EReg` is an `extern` class. Its OCaml body is the
	  shared runtime file `EReg.ml`, which builds a value with `EReg.create`.
	  Stage3 had no construction route for that runtime module, so both a regex
	  literal (`~/x/`, which the parser turns into `new EReg("x", "")`) and an
	  explicit `new EReg(...)` produced the placeholder `(Obj.magic 0)`. The
	  build still succeeded, and the executable crashed on the first `match`.

	What
	- `stage3_ereg` uses literals with the `g`, `i`, and `m` flags,
	  `new EReg(pattern, flags)`, and `match`, `matched`, `matchedLeft`,
	  `matchedRight`, `matchedPos`, `replace`, `split`, and `map`. Regexes live
	  in locals, a static field, an instance field, and a function parameter.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated `Main.ml` must construct every regex through
	  `EReg.create` and must not contain the `(Obj.magic 0)` placeholder outside the
	  unreachable tail that follows a `return`.
**/
class M14Stage3ERegTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function main():Void {
		final source = "test/fixtures/stage3_ereg";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_ereg";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		final generated = File.getContent(outDir + "/Main.ml");
		// `let _ = raise ... in (Obj.magic 0)` is the normal unreachable tail after a
		// return; any other `(Obj.magic 0)` is a placeholder for an unsupported value.
		if (generated.split(" in (Obj.magic 0)").join("").indexOf("(Obj.magic 0)") >= 0)
			throw "Main.ml still contains the (Obj.magic 0) placeholder: " + generated;
		if (generated.indexOf("EReg.create") < 0)
			throw "Main.ml does not construct regexes through EReg.create: " + generated;
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_EREG:PASS");
	}
}
