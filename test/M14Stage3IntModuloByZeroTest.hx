import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds Int modulo by zero with the Stage3 native emitter and compares the
	program with upstream Haxe 4.3.7 on Neko.

	Why
	- Native `HxInt.rem` used OCaml's `Int32.rem`, which raises the OCaml
	  exception `Division_by_zero`. No Haxe `catch` can handle that, so the
	  program stopped with "Fatal error: exception Division_by_zero"
	  (haxe_ocaml-7g1qx).
	- Haxe leaves Int division by zero target-specific. Upstream eval returns
	  the Float NaN even in an Int-typed result. Native Int is an unboxed 32-bit
	  integer that cannot hold NaN, so native follows the static targets (Neko,
	  JVM, C#): it throws a catchable exception.

	What
	- `stage3_int_modulo_by_zero` catches `%` and `%=` by zero and prints normal
	  and negative modulo values. The native executable must print exactly what
	  upstream Neko prints.
	- `stage3_int32_min_modulo_minus_one` checks `-2147483648 % -1` against
	  upstream eval, because Neko crashes on that case on x86-64 Linux.
	- Upstream eval must still print `nan` for the bare case, which keeps the
	  documented divergence visible if eval ever changes.
**/
class M14Stage3IntModuloByZeroTest {
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

	// Redirect both streams to files so a full stderr pipe cannot block the
	// child while stdout is still being read.
	static function output(command:String, arguments:Array<String>, outDir:String):String {
		final stdoutPath = outDir + "/eval.stdout";
		final stderrPath = outDir + "/eval.stderr";
		final quoted = [for (part in [command].concat(arguments)) haxe.SysTools.quoteUnixArg(part)].join(" ");
		Sys.command("sh", [
			"-c",
			quoted + " >" + haxe.SysTools.quoteUnixArg(stdoutPath) + " 2>" + haxe.SysTools.quoteUnixArg(stderrPath)
		]);
		return File.getContent(stdoutPath);
	}

	/**
		Compares `-2147483648 % -1` with upstream eval instead of Neko. The Neko VM
		dies with SIGFPE on this operand pair on x86-64 Linux, so it is not a
		portable oracle here; eval and native both print 0.
	**/
	static function observeMinimumModuloMinusOne(outDir:String):Void {
		final source = "test/fixtures/stage3_int32_min_modulo_minus_one";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir + "/native_minimum");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
	}

	static function main():Void {
		final source = "test/fixtures/stage3_int_modulo_by_zero";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		final outDir = ".tmp/m14_stage3_int_modulo_by_zero";
		deleteRecursive(outDir);
		FileSystem.createDirectory(outDir);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", source, "-main", "Main", "-neko", outDir + "/main.n"]) != 0)
			throw "upstream Neko compilation failed";
		M14Stage3RuntimeFixture.observe({command: "neko", arguments: [outDir + "/main.n"], expected: expected});
		final eval = output("node_modules/.bin/haxe", ["-cp", source, "--run", "Main"], outDir);
		if (!StringTools.startsWith(eval, "nan\n"))
			throw "upstream eval no longer returns nan for Int modulo by zero; revisit the parity decision: " + eval;
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir + "/native");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		observeMinimumModuloMinusOne(outDir);
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INT_MODULO_BY_ZERO:PASS");
	}
}
