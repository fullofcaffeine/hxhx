import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that prints null values and enum values as text with the
	Stage3 native emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- A null String is the runtime null sentinel, not the text `null`. Stage3
	  passed String locals and statics straight to OCaml's `^` and
	  `print_endline`, so they printed the sentinel's raw bytes. A String `+=`
	  on a null local did the same, and a parenthesized concatenation with a
	  null `Null<Int>` operand treated that operand as a string
	  (haxe_ocaml-txs4e, haxe_ocaml-npbsu, haxe_ocaml-aib5d).
	- The runtime conversion had no enum branch, so `"e=" + Red` printed
	  `e=<object>` (haxe_ocaml-aib5d).

	What
	- `stage3_null_text` prints null and present Strings through concatenation
	  on either side, `Sys.println`, `Std.string`, interpolation, `join`,
	  `Array.toString` and String `+=` (statement and value). It prints null
	  `Null<Int>` values, enum values with and without arguments, null enum
	  values, enum arguments of String, enum and anonymous types, and static
	  fields without an initializer.
	- The native executable must print exactly what upstream Haxe prints.
**/
class M14Stage3NullTextTest {
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
		An uninitialized static keeps the carrier its type needs. An unboxed
		number or Bool (also through an abstract) holds an immediate, never the
		null sentinel. A reference type holds the null sentinel.
	**/
	static function requireStaticDefaults(outDir:String):Void {
		var source = "";
		for (entry in FileSystem.readDirectory(outDir))
			if (StringTools.endsWith(entry, ".ml"))
				source += File.getContent(Path.join([outDir, entry])) + "\n";
		final expected = [
			"let kind = 0",
			"let meters = 0.",
			"let count = 0",
			"let flag = false",
			"let plain = 0",
			"let ratio = 0.",
			"let slabel = (Obj.magic HxRuntime.hx_null)",
			"let scount = (Obj.magic HxRuntime.hx_null)",
			"let sflag = (Obj.magic HxRuntime.hx_null)",
			"let sitems = (Obj.magic HxRuntime.hx_null)"
		];
		for (line in expected)
			if (source.indexOf("\n" + line + "\n") < 0)
				throw "missing static default: " + line;
		for (name in ["unsigned", "int32"]) {
			final at = source.indexOf("\nlet " + name + " = ");
			if (at < 0
				|| source.substr(at + 1, ("let " + name + " = (Obj.magic HxRuntime.hx_null)").length) == "let " + name + " = (Obj.magic HxRuntime.hx_null)")
				throw "an Int-backed static must not hold the null sentinel: " + name;
		}
	}

	static function main():Void {
		final source = "test/fixtures/stage3_null_text";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_null_text";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		requireStaticDefaults(outDir);
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_NULL_TEXT:PASS");
	}
}
