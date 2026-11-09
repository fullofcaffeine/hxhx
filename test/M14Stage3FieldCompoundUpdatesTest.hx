import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds compound updates of anonymous-structure and Float instance fields
	with the Stage3 native emitter and compares the program with upstream Haxe.

	Why
	- `o.n += 2` on an anonymous structure and `h.ratio -= 0.5` on a Float
	  instance field became the `(Obj.magic 0)` placeholder natively. The
	  statement was dropped, so the program printed the old value.

	What
	- `stage3_field_compound_updates` covers statement and value positions,
	  Int and Float right operands, receivers and right operands that record
	  their evaluation order, a right operand that updates the same field, and
	  a field declared with a type parameter.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
**/
class M14Stage3FieldCompoundUpdatesTest {
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
		final source = "test/fixtures/stage3_field_compound_updates";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_field_compound_updates";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		expectRefused("class Main { static function main() { final o = {n: 1}; final d:Dynamic = 2; o.n += d; } }", source, "`n`");
		expectRefused("class H { public var f:Float = 1.5; public function new() {} }\n"
			+ "class Main { static function main() { final h = new H(); final d:Dynamic = 2; h.f += d; } }",
			source, "`f`");
		Sys.println("M14_STAGE3_FIELD_COMPOUND_UPDATES:PASS");
	}

	/** An update that has no native lowering must stop compilation, not emit a placeholder that drops it. */
	static function expectRefused(code:String, root:String, fieldName:String):Void {
		final outDir = ".tmp/m14_stage3_field_compound_refused";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: code, path: root + "/Main.hx", root: root});
		var message = "";
		try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		} catch (error:Any) {
			message = Std.string(error);
		}
		deleteRecursive(outDir);
		if (message.indexOf("refusing to emit a placeholder") == -1 || message.indexOf(fieldName) == -1)
			throw "expected a named emit-time refusal for " + fieldName + ", got: " + message;
	}
}
