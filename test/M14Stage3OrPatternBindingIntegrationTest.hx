import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds or-patterns that bind one name in every alternative with the Stage3
	native emitter and compares the program with upstream Haxe.

	Why
	- `case A(s) | B(s):` binds `s` from whichever alternative matched. The old
	  version of this test switched on a `Dynamic` value with undeclared
	  constructors `A` and `B`, which upstream Haxe rejects, and it checked an
	  exact line of emitted OCaml. It failed on origin/main with "OCaml named
	  pattern requires its exact selected declaration", because typing could
	  not select a declaration for those constructors.

	What
	- `stage3_or_pattern_binding` covers alternatives that read the payload
	  from the same position, from different positions, and from different
	  constructors, plus an or-pattern nested inside a constructor and an
	  or-pattern with a guard.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3OrPatternBindingIntegrationTest {
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
		final source = "test/fixtures/stage3_or_pattern_binding";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_or_pattern_binding";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_OR_PATTERN_BINDING:PASS");
	}
}
