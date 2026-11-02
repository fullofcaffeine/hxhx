import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a bitwise compound assignment program with the Stage3 native emitter
	and compares its output with upstream Haxe 4.3.7.

	Why
	- `x |= 1`, `x <<= 2` and the other bitwise compound operators had no
	  native lowering for Int locals, instance fields, `Array<Int>` elements, or
	  anonymous-structure fields. Local and field updates were dropped, and
	  array updates stopped emission. Compound updates of anonymous-structure
	  fields, arithmetic ones included, removed the whole statement.

	What
	- `stage3_bitwise_compound` applies `|= &= ^= <<= >>= >>>=` to Int and
	  `haxe.Int32` locals, fields, anonymous fields and array elements, as
	  statements and as values.
	- The fixture also covers Int `%=` on fields, structure fields, array
	  elements and locals, which keeps the sign of the dividend.
	- The native executable must print exactly what upstream Haxe prints.
	- A compound update of an optional structure field (`{?x:Int}`) stops
	  with a named error instead of being dropped.
**/
class M14Stage3BitwiseCompoundTest {
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

	/**
		A compound update of an optional structure field has no native lowering yet
		(haxe_ocaml-gaa3a). It must stop with a named error, not drop the statement.
	**/
	static function rejectOptionalStructureField():Void {
		final source = ".tmp/m14_stage3_bitwise_compound_optional";
		deleteRecursive(source);
		FileSystem.createDirectory(source);
		final path = source + "/Main.hx";
		File.saveContent(path, "class Main { static function main():Void { final opt:{?x:Int} = {x: 4}; opt.x <<= 1; Sys.println(\"x \" + opt.x); } }\n");
		var message:Null<String> = null;
		try {
			final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), source + "/out");
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		deleteRecursive(source);
		final expected = "unsupported native OCaml compound assignment <<= on optional structure field `x`";
		if (message == null || message.indexOf(expected) < 0)
			throw "expected <" + expected + ">, got <" + message + ">";
		Sys.println("M14_STAGE3_BITWISE_COMPOUND_OPTIONAL_FIELD_REJECTED:PASS");
	}

	static function main():Void {
		final source = "test/fixtures/stage3_bitwise_compound";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_BITWISE_COMPOUND_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_bitwise_compound";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		final generated = File.getContent(outDir + "/Main.ml");
		if (generated.indexOf("ignore ((Obj.magic 0))") >= 0)
			throw "Stage3 replaced a compound assignment with the placeholder";
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_BITWISE_COMPOUND_NATIVE:PASS");
		rejectOptionalStructureField();
	}
}
