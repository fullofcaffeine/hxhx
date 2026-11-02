import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that converts Floats to strings with the Stage3 native
	emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- Native output used OCaml's `string_of_float`, which keeps 12 significant
	  digits and adds a trailing `.` to whole numbers. `Std.string(2.0)` printed
	  `2.` and `7 / 3` printed `2.33333333333`, where upstream Haxe prints `2`
	  and `2.33333333333333348`.

	What
	- `stage3_float_string` covers whole numbers, signed zero, values that need
	  more than 12 significant digits, short values, exponent forms, a subnormal
	  value, a parsed value, and Floats stored in Dynamic, `Null<Float>`, arrays,
	  anonymous objects, `StringBuf`, concatenation, and interpolation.
	- The native executable must print exactly what upstream Haxe prints.
	- `NaN` and the infinities are not covered: their text differs between
	  upstream targets (eval prints `nan`, `infinity`, `neg_infinity`), and
	  that choice is outside this fixture.
**/
class M14Stage3FloatStringTest {
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
		final source = "test/fixtures/stage3_float_string";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_float_string";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_FLOAT_STRING:PASS");
	}
}
