import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `++`/`--` on array elements and fields with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Stage3 lowered `++` and `--` only on mutable locals and on Int instance
	  fields. On an array element (`a[i]++`, `--a[i]`), a Float field, or a
	  field of an anonymous structure, the update became the `(Obj.magic 0)`
	  placeholder. The statement was dropped, so the value never changed, and
	  a value-position result was a placeholder.

	What
	- `stage3_increment_places` covers prefix and postfix forms in statement
	  and value positions on `Int`, `Float`, `Int32`, and `Null<Int>` array
	  elements, Int and Float instance fields, and anonymous-structure fields.
	  It also checks that the array and index expressions run once, in order.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3IncrementPlacesTest {
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
		final source = "test/fixtures/stage3_increment_places";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_increment_places";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INCREMENT_PLACES:PASS");
	}
}
