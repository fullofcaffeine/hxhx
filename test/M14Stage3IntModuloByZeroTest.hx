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

	static function output(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		process.stderr.readAll();
		process.exitCode();
		process.close();
		return stdout;
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
		final eval = output("node_modules/.bin/haxe", ["-cp", source, "--run", "Main"]);
		if (!StringTools.startsWith(eval, "nan\n"))
			throw "upstream eval no longer returns nan for Int modulo by zero; revisit the parity decision: " + eval;
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir + "/native");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INT_MODULO_BY_ZERO:PASS");
	}
}
