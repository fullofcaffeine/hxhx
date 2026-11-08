import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `Std.int` of out-of-range Floats with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Native `Std.int` used OCaml's `int_of_float`, which yields a 63-bit
	  value, so `Std.int(4294967295.0)` was 4294967295. Upstream eval wraps
	  the truncated value into the signed 32-bit range and gives -1. Later Int
	  arithmetic and printing then disagreed with upstream.

	What
	- `stage3_std_int_wrap` covers NaN, ±0.5, ±1.9, -0.0, the values around
	  ±2^31 and 2^32, ±3e9, ±1e10, 2^53, Int arithmetic on the result, and
	  `Std.int` of a UInt above 0x7FFFFFFF. The native executable must print
	  exactly what upstream Haxe 4.3.7 eval prints.
	- ±Infinity and |x| >= 2^63 are excluded. Their eval results depend on the
	  CPU's float-to-int conversion, and upstream targets disagree. See the
	  fixture README and docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md.
**/
class M14Stage3StdIntWrapTest {
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
		final source = "test/fixtures/stage3_std_int_wrap";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_std_int_wrap";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_STD_INT_WRAP:PASS");
	}
}
