import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that calls `Math` functions with Int arguments and uses
	`Null<Int>` array indices and Map keys, with the Stage3 native emitter, and
	compares its output with upstream Haxe 4.3.7.

	Why
	- Every `Math` function takes Float arguments. `Math.abs(-2)` was emitted as
	  `abs_float ((HxInt.neg (2)))` and failed to compile, `Math.isNaN(3)` passed
	  an int to `classify_float`, and Stage3 replaced `Math.pow`, `Math.floor`,
	  `Math.log` and `Math.fround` with a placeholder in its untyped fallback.
	- Indexed access required an exact `Int` index, so `a[i] = 5` with
	  `i:Null<Int>` was dropped.

	What
	- `stage3_math_int_nullable_index` covers `Math.abs/max/min/round/floor/ceil/
	  sqrt/pow/exp/log/sin/cos/isNaN/isFinite` with Int literals, Int calls and
	  Int locals, and `Null<Int>` indices for array reads, writes and compound
	  updates. `Null<Int>` Map keys are covered by PR #151.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3MathIntNullableIndexTest {
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
		final source = "test/fixtures/stage3_math_int_nullable_index";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_MATH_INT_NULLABLE_INDEX_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_math_int_nullable_index";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_MATH_INT_NULLABLE_INDEX_NATIVE:PASS");
	}
}
