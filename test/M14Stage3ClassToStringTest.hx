import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that turns class instances into text with the Stage3
	native emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- Stage3 stores a class instance as a class-tagged `HxAnon` object, and its
	  methods are module functions. The runtime string conversion printed the
	  stored fields (`{name: rex}`) instead of calling `toString()`
	  (haxe_ocaml-czx3v, haxe_ocaml-x1ekz).

	What
	- `stage3_class_to_string` converts instances through `Std.string`,
	  concatenation, `Array.join`, `Array.toString`, `Std.string` of an array,
	  Dynamic storage, a mixed `Array<Dynamic>`, and an anonymous-object field.
	- It covers an override called through a supertype-typed value, a method
	  inherited without an override, a private `toString` with an inferred
	  return type, an inline `toString`, a class without `toString` (upstream
	  eval prints the class name), and a null instance.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3ClassToStringTest {
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
		final source = "test/fixtures/stage3_class_to_string";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_class_to_string";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_CLASS_TO_STRING:PASS");
	}
}
