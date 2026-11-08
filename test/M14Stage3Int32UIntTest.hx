import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `Int32` update and `UInt` text programs with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- `++`/`--` on an `Int32` local, parameter, or field left the value
	  unchanged natively (Bead haxe_ocaml-xojcc). PR #136, which this branch is
	  stacked on, lowers those updates. This test pins them in statement and
	  value positions, including the wrap at 2^31.
	- A `UInt` above `0x7FFFFFFF` printed as a negative Int (`-1` for
	  `0xFFFFFFFF`) natively (Bead haxe_ocaml-5uhcj). Upstream converts a value
	  whose static type is `UInt` through `UInt.toString`, which prints the
	  unsigned value.

	What
	- `stage3_int32_uint` covers Int32 updates and UInt `Std.string`,
	  concatenation, comparisons, division, remainder, wrap-around, and
	  `++`/`--`. It also covers the cases that print the erased Int on upstream
	  too: `join`, `Std.string(array)`, and a bare `Sys.println(uint)`. The
	  native executable must print exactly what upstream Haxe 4.3.7 prints.
	- `trace(uint)` must print the unsigned value. Native `trace` omits
	  upstream's `File.hx:line:` prefix (Bead haxe_ocaml-00tpu), so this check
	  compares only the value.
**/
class M14Stage3Int32UIntTest {
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

	static function native(source:String, path:String, root:String, label:String):String {
		final outDir = ".tmp/m14_stage3_int32_uint_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		return EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
	}

	static function main():Void {
		final root = "test/fixtures/stage3_int32_uint";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final executable = native(File.getContent(root + "/Main.hx"), root + "/Main.hx", root, "fixture");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_INT32_UINT:PASS");

		final traced = native([
			'class Main {',
			'  static function main():Void {',
			'    final big:UInt = 0xFFFFFFFF;',
			'    trace(big);',
			'  }',
			'}',
			''
		].join("\n"), "Main.hx", ".", "trace");
		M14Stage3RuntimeFixture.observe({command: traced, arguments: [], expected: "4294967295\n"});
		deleteRecursive(".tmp/m14_stage3_int32_uint_fixture");
		deleteRecursive(".tmp/m14_stage3_int32_uint_trace");
		Sys.println("M14_STAGE3_UINT_TRACE:PASS");
	}
}
