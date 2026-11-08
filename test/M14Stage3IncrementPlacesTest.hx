import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `++`/`--` on array elements and fields with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Stage3 lowered `++` and `--` only on mutable locals and on Int instance
	  fields. On an array element (`a[i]++`, `--a[i]`), a Float field, or a
	  field of an anonymous structure, the update became the `(Obj.magic 0)`
	  placeholder. The statement was dropped, so the value never changed, and
	  a value-position result was a placeholder.

	What
	- `stage3_increment_places` covers prefix and postfix forms in statement
	  and value positions on `Int`, `Float`, `Int32`, and `Null<Int>` array
	  elements, Int and Float instance fields, and anonymous-structure fields.
	  It also checks that the array and index expressions run once, in order.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- `stage3_increment_places_int_in_float` is known failing for one remaining
	  reason: an Int literal stored into a Float slot is now promoted, so `++`
	  no longer crashes, but a whole-number Float prints as `2.` where upstream
	  prints `2` (Bead haxe_ocaml-vzr17). The test requires exactly that known
	  output, so a crash, a wrong number, or the formatting fix is noticed. Once
	  the output matches upstream, the lines move into the main fixture.
**/
class M14Stage3IncrementPlacesTest {
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

	/** Check upstream, then build the native executable; returns it with the expected output. */
	static function build(source:String, label:String):{executable:String, expected:String, outDir:String} {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_increment_places_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		return {executable: EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir), expected: expected, outDir: outDir};
	}

	static function main():Void {
		final main = build("test/fixtures/stage3_increment_places", "main");
		M14Stage3RuntimeFixture.observe({command: main.executable, arguments: [], expected: main.expected});
		deleteRecursive(main.outDir);
		Sys.println("M14_STAGE3_INCREMENT_PLACES:PASS");
		// Int literals stored into Float slots are promoted, so the native run must exit cleanly.
		// Only whole-number Float printing still differs from upstream (Bead haxe_ocaml-vzr17).
		final known = build("test/fixtures/stage3_increment_places_int_in_float", "int_in_float");
		// When vzr17 lands this observation fails: fold the fixture into stage3_increment_places.
		M14Stage3RuntimeFixture.observe({command: known.executable, arguments: [], expected: "int literal element: 2.,2.\nint literal field: 4.\n"});
		deleteRecursive(known.outDir);
		Sys.println("M14_STAGE3_INCREMENT_PLACES_INT_IN_FLOAT:KNOWN_FAILING (haxe_ocaml-vzr17)");
	}
}
