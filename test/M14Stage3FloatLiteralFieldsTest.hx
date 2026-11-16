import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that writes Int values into Float fields of anonymous
	structure literals with the Stage3 native emitter and compares it with
	upstream Haxe.

	Why
	- `var o:{f:Float} = {f: 1}` is valid Haxe: the Int is promoted to Float. The
	  native literal stored the OCaml int `1` in that slot. A later read as a Float
	  treats the immediate value `1` as a pointer to a boxed double, so the program
	  crashed with SIGSEGV (exit 139) or printed a wrong number.

	What
	- `stage3_float_literal_fields` reaches a Float field through every place an
	  expected structure type enters a literal: declarations, assignment, call
	  arguments, returns, nested structures, arrays and Maps of structures,
	  typedef-named structures, and optional or nullable fields. Int and Dynamic
	  fields are controls and must keep the Int.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated OCaml must promote the literal and keep the Int control, so a
	  later change cannot pass by an unrelated route.
**/
class M14Stage3FloatLiteralFieldsTest {
	static final fixture = "test/fixtures/stage3_float_literal_fields";

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
		final path = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_float_literal_fields";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_FLOAT_LITERAL_FIELDS_WHOLE_FILE:PASS");
		deleteRecursive(outDir);
	}
}
