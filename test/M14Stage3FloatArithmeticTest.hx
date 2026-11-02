import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that does arithmetic on Float values with the Stage3 native
	emitter and compares its output with upstream Haxe.

	Why
	- Stage3 chose the OCaml operator for `a + b` (`+` for Int, `+.` for Float,
	  `^` for String) by guessing each operand's type from its source shape.
	  A Float method result, a field of type `T` instantiated with Float, an
	  `Array<Float>` element, and `this` in a Float-backed abstract were not
	  recognized. `c.get() + 0.5` was concatenated as text ("1.250.5"),
	  `g.value / 8` and `a[0] + a[1]` became the placeholder `(Obj.magic 0)`
	  (printing 0, or crashing when used again), and `this / 2` printed 0.

	What
	- `stage3_float_arithmetic` applies `+ - * / %`, comparisons, and `+=` to
	  each of those Float sources, updates Float locals, fields, and
	  `Array<Float>` elements with Int values, mixes Float with Int, divides two Ints,
	  feeds Int branches into Float-valued `if` and `switch`, and concatenates
	  Strings with Floats.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated OCaml must use Float operators for `a[0] + a[1]` and for
	  the `Array<Float>` compound update, so the check cannot pass by an unrelated
	  route.
**/
class M14Stage3FloatArithmeticTest {
	static final fixture = "test/fixtures/stage3_float_arithmetic";

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

	static function requireText(source:String, text:String, reason:String):Void {
		if (source.indexOf(text) < 0)
			throw reason + ": missing `" + text + "` in generated Main.ml";
	}

	static function main():Void {
		final path = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_float_arithmetic";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_FLOAT_ARITHMETIC_WHOLE_FILE:PASS");
		final main = File.getContent(outDir + "/Main.ml");
		// The old fallback printed the placeholder instead of `a[0] + a[1]`.
		if (main.indexOf("HxDynamic.toStdString (Obj.repr ((Obj.magic 0)))") >= 0)
			throw "Float arithmetic must not print the `(Obj.magic 0)` placeholder";
		// Both indexed reads are bound in source order before the Float addition.
		requireText(main,
			"let __hx_ordered_right = ((let __hx_indexed_array = (a) in let __hx_indexed_index = (1) in HxBootArray.get (Obj.magic __hx_indexed_array) __hx_indexed_index)) in ((__hx_ordered_left) +. (__hx_ordered_right))",
			"`a[0] + a[1]` must use the OCaml Float addition");
		requireText(main, "__hx_indexed_old +. __hx_indexed_right", "`a[0] += count()` must use the OCaml Float addition");
		Sys.println("M14_STAGE3_FLOAT_ARITHMETIC_OPERATORS:PASS");
		deleteRecursive(outDir);
	}
}
