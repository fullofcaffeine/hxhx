import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a `haxe.Int32` and `haxe.Int64` arithmetic program with the Stage3
	native emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- `Sys.println("x " + (i32 + 1))` crashed the native program with SIGSEGV.
	  The typer represents that operand as a cast of an `Int32` temporary to
	  `Int`. Stage3 did not recognize the cast as a number, so it passed the
	  integer straight to OCaml's string concatenation `^`, which then read the
	  integer as a string pointer.
	- `counter++` on an `Int32` local did nothing. The inlined operator body
	  writes `this = clamp(this)` back to the local inside an expression, and
	  Stage3 replaced that value-position local assignment with a placeholder.
	- `i64++` read and wrote the private `high`/`low` words through the
	  anonymous-object lookup, which finds no fields on the Int64 record, so the
	  value did not change.
	- `Int64.compare` returned only -1, 0, or 1. Upstream returns the word
	  difference itself (for example -2147483647), and callers can print it.

	What
	- `stage3_int32_int64_arithmetic` exercises Int32 `+ - * / %`, negation,
	  shifts, bitwise operators, comparisons, 32-bit wraparound, increment and
	  decrement, mixed `Int`/`Int32` operands, and Int64
	  make/add/sub/mul/div/mod/compare/ucompare/toStr/ofInt/toInt/increment.
	- The fixture also covers `text += (i32 + 1)`, a user class with its own
	  `high`/`low` fields, and local assignments used as values, including an
	  Int stored in a `Float` local.
	- The native executable must print exactly what upstream Haxe prints.
	- Prefix `++value`/`--value` on an Int64 is not supported yet: its inline
	  body contains an `if` statement that shared preparation cannot place in an
	  expression. It must stop with that named error instead of producing a
	  program (follow-up: haxe_ocaml-bcafx).
**/
class M14Stage3Int32Int64ArithmeticTest {
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

	/** Prefix Int64 updates are rejected before emission with a named error. */
	static function rejectPrefixInt64Update():Void {
		final source = ".tmp/m14_stage3_int64_prefix_update";
		deleteRecursive(source);
		FileSystem.createDirectory(source);
		final path = source + "/Main.hx";
		File.saveContent(path,
			"class Main { static function main():Void { var value = haxe.Int64.ofInt(9); ++value; Sys.println(haxe.Int64.toStr(value)); } }\n");
		var message:Null<String> = null;
		try {
			M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		deleteRecursive(source);
		final expected = "Inline abstract unary helper contains unsupported typed statement If: haxe.Int64#instance:preIncrement()";
		if (message == null || message.indexOf(expected) < 0)
			throw "expected <" + expected + ">, got <" + message + ">";
		Sys.println("M14_STAGE3_INT64_PREFIX_UPDATE_REJECTED:PASS");
	}

	static function main():Void {
		final source = "test/fixtures/stage3_int32_int64_arithmetic";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_INT32_INT64_ARITHMETIC_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_int32_int64_arithmetic";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		// OCaml evaluates application arguments right to left. A word write must bind
		// its receiver before its value, like every other ordered Stage3 call.
		final generated = File.getContent(outDir + "/Main.ml");
		if (generated.indexOf("(Haxe_Int64.set_low) in let __hx_call_argument") < 0)
			throw "Stage3 Int64 word writes must evaluate the receiver before the value";
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INT32_INT64_ARITHMETIC_NATIVE:PASS");
		rejectPrefixInt64Update();
	}
}
