import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that stores `Null<Int>`, `Null<Float>` and Int values into
	Float destinations with the Stage3 native emitter, and compares its output
	with upstream Haxe 4.3.7.

	Why
	- A `Null<Int>` value lives in a nullable carrier: an OCaml `Obj.t` that
	  holds an immediate int, or the null sentinel. Stored unchanged into a
	  Float class field, an `Array<Float>` slot, a Float local or a Float
	  return, it made a later Float read dereference that immediate int, and
	  the native program crashed with SIGSEGV and printed nothing.
	- Int values written into Float fields of an anonymous structure
	  (`{x: 1, y: count()}` typed `{x:Float, y:Float}`, then `p.x = count()`)
	  were stored as ints and crashed the same way.

	What
	- `stage3_nullable_int_to_float` stores such values into each of those
	  destinations and reads them back as Float.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3NullableIntToFloatTest {
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
		final source = "test/fixtures/stage3_nullable_int_to_float";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_INT_TO_FLOAT_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_nullable_int_to_float";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_NULLABLE_INT_TO_FLOAT_NATIVE:PASS");
	}
}
