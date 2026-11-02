import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `Math` rounding programs with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- The runtime `Math.floor`/`ceil`/`round` used a bare `int_of_float`, so
	  `Math.floor(2^31)` returned 2147483648 where upstream eval gives 0.
	  `Math.fround` was the identity function, and `ffloor`/`fceil` went
	  through an Int, losing NaN, infinities, large values, and -0.0.
	- Stage3 emitted `Math.floor` and `Math.fround` as the `(Obj.magic 0)`
	  placeholder. It inlined `Math.round` as `int_of_float (floor ...)`, where
	  an unqualified `floor` could resolve to a local variable named `floor`;
	  that program crashed with SIGSEGV.

	What
	- `stage3_math_rounding` covers ties, signed zero, NaN, the infinities,
	  and values around ±2^31, 2^32, 3e9, 1e10, 2^53, and 1e20, for all six
	  functions. The native executable must print exactly what upstream Haxe
	  4.3.7 eval prints. The same program runs through the reflaxe.ocaml backend
	  as the portable fixture `math_rounding_wrap`.
**/
class M14Stage3MathRoundingTest {
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
		final source = "test/fixtures/stage3_math_rounding";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_math_rounding";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_MATH_ROUNDING:PASS");
	}
}
