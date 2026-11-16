import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that passes Int values into Float destinations with the
	Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Haxe promotes an Int value to Float when it enters a Float destination.
	  Stage3 promoted only Int literals and Int locals, and only when the
	  parameter was written `Float`. With `floats:Box<Float>`, the call
	  `floats.put(2)` passed the OCaml int `2` to code that reads a boxed float,
	  so the native program crashed with SIGSEGV. `var f:Float = ints.get()`
	  kept an OCaml int in a float binding and also crashed or failed to build.

	What
	- `stage3_float_type_arguments` passes Int literals, Int results, and Int
	  expressions through a generic interface, a generic class (constructor,
	  method, and a field of type `T`), a generic method, Float locals,
	  arguments, and returns, `Null<Float>` type arguments, and `Array<Float>`
	  writes. `Cell<Int>` and `Cell<Dynamic>` show that Int values stay Int when
	  the destination is not Float.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated OCaml must promote `floats.put(2)` and must not promote the
	  `Cell<Int>` argument, so a later change cannot pass by an unrelated route.
**/
class M14Stage3FloatTypeArgumentsTest {
	static final fixture = "test/fixtures/stage3_float_type_arguments";

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
		final outDir = ".tmp/m14_stage3_float_type_arguments";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_FLOAT_TYPE_ARGUMENTS_WHOLE_FILE:PASS");
		final main = File.getContent(outDir + "/Main.ml");
		requireText(main, "let __hx_call_argument_1 = ((float_of_int 2)) in", "Box<Float>.put(2) must promote its Int argument");
		requireText(main, "let __hx_ctor_arg_0 = (7) in", "Cell<Int> must keep its Int constructor argument");
		requireText(main, "let __hx_call_argument_1 = ((9)) in", "Cell<Int>.put(9) must keep its Int argument");
		Sys.println("M14_STAGE3_FLOAT_TYPE_ARGUMENTS_PROMOTION_SITES:PASS");
		deleteRecursive(outDir);
	}
}
