import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `Math.pow` and `Math.log` programs with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- Stage3 matched `Math.pow` and `Math.log` by name and emitted the
	  `(Obj.magic 0)` placeholder for both, so a program that used them
	  crashed with signal 139. The runtime `Math` module already implements
	  them with the C library's `pow` and `log`, as upstream eval does.

	What
	- `stage3_math_pow_log` covers exact results, Int arguments, and the IEEE
	  special values (NaN, ±Infinity, signed zero, overflow). The native
	  executable must print exactly what upstream Haxe 4.3.7 eval prints.
**/
class M14Stage3MathPowLogTest {
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
		final source = "test/fixtures/stage3_math_pow_log";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_math_pow_log";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_MATH_POW_LOG:PASS");
	}
}
