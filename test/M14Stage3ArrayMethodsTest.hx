import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds Array programs with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- Stage3 output contains a generated `Array` OCaml module built from the
	  standard `Array` class. Methods without a Haxe body, such as `sort`,
	  `reverse`, or `pop`, are empty stubs in that module. A typed call without
	  a native adapter used to bind to such a stub: OCaml compiled it, and the
	  program silently did nothing or returned a placeholder.
	- Upstream utest sorts method names with a callback that passes its
	  `String` parameters both to a typed lookup method and to
	  `Reflect.compare`. The Stage3 `Reflect.compare` shim accepted only
	  `Obj.t`, so OCaml rejected the same value as both `string` and `Obj.t`.

	What
	- `sort_callback_shapes` is shared with the Reflaxe OCaml portable fixture
	  of the same name. It sorts anonymous records, uses a block-bodied
	  comparator, and uses the utest-style `String` comparator.
	- `stage3_array_methods` prints the return value and the resulting array
	  for every bodiless Array method, so a no-op is visible.
	- Each native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A method without an adapter must stop emission with a named error rather
	  than reach a stub.
**/
class M14Stage3ArrayMethodsTest {
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

	static function compareWithUpstream(label:String, source:String, expectedPath:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(expectedPath);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_array_methods_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_ARRAY_METHODS_" + label.toUpperCase() + ":PASS");
	}

	static function main():Void {
		compareWithUpstream("sort_callbacks", "test/portable/fixtures/sort_callback_shapes/src", "test/portable/fixtures/sort_callback_shapes/expected.stdout");
		compareWithUpstream("bodiless", "test/fixtures/stage3_array_methods", "test/fixtures/stage3_array_methods/expected.stdout");
	}
}
