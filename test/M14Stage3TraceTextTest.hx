import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that traces values and prints enum values with Bool
	arguments with the Stage3 native emitter, and compares its output with
	upstream Haxe 4.3.7.

	Why
	- Native `trace(x)` printed only the first argument, with no `file:line: `
	  prefix. It printed a Bool static as `1`, and it emitted nothing for a call
	  with extra arguments (haxe_ocaml-00tpu).
	- An enum payload stores a Bool argument as a raw OCaml bool, so
	  `Flagged(true)` printed `Flagged(1)` (haxe_ocaml-k3jwd).

	What
	- `stage3_trace_text` traces Strings, a Bool static, several arguments,
	  null, a null String, enum values, a direct `haxe.Log.trace` call, and a
	  trace in another module. It prints enum values with Bool and `Null<Bool>`
	  arguments, and a field String `+=` with null operands.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3TraceTextTest {
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
		final source = "test/fixtures/stage3_trace_text";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_trace_text";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_TRACE_TEXT:PASS");
	}
}
