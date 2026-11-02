import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds indexed array writes with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- A statement such as `values[1] = 7` used to compile to OCaml `()` when the
	  write was the whole statement. OCaml accepted the program, and the native
	  executable ran without changing the array, so the bug was silent.

	What
	- `stage3_indexed_array_assignment` writes through a function-parameter
	  alias, repeats writes to one slot, grows an array by writing past its end,
	  writes String, Float, and nullable Int elements, writes inside a loop, and
	  records the order in which receiver, index, and value are evaluated.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints
	  with `--run`.
**/
class M14Stage3IndexedArrayAssignmentTest {
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
		final source = "test/fixtures/stage3_indexed_array_assignment";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_indexed_array_assignment";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INDEXED_ARRAY_ASSIGNMENT:PASS");
	}
}
