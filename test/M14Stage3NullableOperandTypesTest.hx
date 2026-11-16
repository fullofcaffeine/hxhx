import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program whose arithmetic has nullable or Dynamic operands with the
	Stage3 native emitter and compares its output with upstream Haxe.

	Why
	- The typer gave such arithmetic no type when the result went straight into
	  a call: `(ratio *= 2) + 0.5` with `ratio:Null<Float>`,
	  `floats.get(k) + x` on a `Map<String, Float>`, `Std.int(s.charCodeAt(0) / 2)`
	  and `Sys.println(boxed + 1)` with `boxed:Dynamic` all stopped with
	  "selected call conversion does not satisfy its retained parameter:
	  unknown -> ...".

	What
	- `stage3_nullable_operand_types` uses those values as operands of
	  `+ - * /`, in locals, as call arguments, and in Sys.println.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3NullableOperandTypesTest {
	static final fixture = "test/fixtures/stage3_nullable_operand_types";

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
		final outDir = ".tmp/m14_stage3_nullable_operand_types";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_OPERAND_TYPES_WHOLE_FILE:PASS");
		deleteRecursive(outDir);
	}
}
