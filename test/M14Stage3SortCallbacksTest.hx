import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds one sort-callback program with the Stage3 native emitter and compares it with Haxe.

	Why
	- Upstream utest sorts method names with a callback that passes its `String`
	  parameters both to a typed lookup method and to `Reflect.compare`. Stage3
	  generated `Reflect.compare x y` against a bootstrap shim whose parameters
	  were fixed to `Obj.t`, so OCaml rejected the same value as both `string`
	  and `Obj.t`.
	- A typed `Array.sort` call also fell through to `Array.sort receiver
	  comparator`, which OCaml resolves to `Stdlib.Array.sort`.

	What
	- The program is shared with the Reflaxe OCaml portable fixture
	  `test/portable/fixtures/sort_callback_shapes`, so both native backends
	  must print the same order as upstream Haxe 4.3.7 for anonymous-record,
	  block-bodied, and String `Reflect.compare` comparators.
**/
class M14Stage3SortCallbacksTest {
	static final root = "test/portable/fixtures/sort_callback_shapes";

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
		final source = root + "/src";
		final path = source + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_SORT_CALLBACKS_UPSTREAM:PASS");

		final outDir = ".tmp/m14_stage3_sort_callbacks";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_SORT_CALLBACKS_NATIVE:PASS");
	}
}
