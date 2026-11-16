import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that turns Bool values into text with the Stage3 native
	emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- An OCaml `bool` and `int` share one runtime shape. Static Bool fields,
	  `Null<Bool>` locals, optional Bool parameters, Map reads, `is` results and
	  `Array<Bool>.join` reached the runtime conversion without their type and
	  printed `1`/`0` (haxe_ocaml-agc6n, haxe_ocaml-caxgt).

	What
	- `stage3_bool_text` prints Bool values through concatenation, String `+=`,
	  `join`, `Std.string`, `Sys.println`, `Array.toString`, interpolation,
	  `StringBuf`, anonymous objects and Dynamic values, including `Null<Bool>`
	  values and an abstract over Bool. Integers must still print `1` and `0`.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3BoolTextTest {
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
		final source = "test/fixtures/stage3_bool_text";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_bool_text";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_BOOL_TEXT:PASS");
	}
}
