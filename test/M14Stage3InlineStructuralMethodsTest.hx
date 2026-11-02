import sys.FileSystem;

/**
	Builds a program that uses inline structural method types with the Stage3
	native emitter and compares its output with upstream Haxe.

	Why
	- `function provide():{ function value():Int; } return new Answer();` used
	  to type its return as an unresolved annotation, because the parser joined
	  `function value` into one word. After that was repaired, the native
	  program still crashed: a class instance keeps its methods as module-level
	  OCaml functions, not in its field storage, so reading `value` through the
	  structure type found nothing and the call jumped through a null value.

	What
	- `stage3_inline_structural_methods` calls, stores, and passes method fields
	  of inline structure types, filled by object literals and by class
	  instances (including an overriding subclass), plus a variable field that
	  holds a function and a named typedef for comparison.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3InlineStructuralMethodsTest {
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
		final source = "test/fixtures/stage3_inline_structural_methods";
		final path = source + "/Main.hx";
		final expected = sys.io.File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_inline_structural_methods";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: sys.io.File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INLINE_STRUCTURAL_METHODS:PASS");
	}
}
