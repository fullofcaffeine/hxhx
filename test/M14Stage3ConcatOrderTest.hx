import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a String concatenation program with the Stage3 native emitter and
	compares its output with upstream Haxe 4.3.7.

	Why
	- Stage3 renders `a + b` on Strings as OCaml's `a ^ b`. OCaml evaluates the
	  arguments of `^` right to left, so `"x" + f() + g()` called `g` before `f`.
	- An expression printed with `Sys.println` went through a path that treated
	  every `+` as concatenation, so `Sys.println(ratio + 0.25)` printed
	  `0.50.25` instead of `0.75`, and `n + 3 + "x"` printed `23x` instead of `5x`.

	What
	- `stage3_concat_order` prints the order in which concatenation operands
	  run, and prints numeric `+` results directly and inside concatenations.
	- The native executable must print exactly what upstream Haxe prints.
	- A concatenation with a literal or immutable-local operand keeps the plain
	  `^` form, so ordering adds no bindings where order cannot be observed.
**/
class M14Stage3ConcatOrderTest {
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
		final source = "test/fixtures/stage3_concat_order";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_CONCAT_ORDER_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_concat_order";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		final generated = File.getContent(outDir + "/Main.ml");
		if (generated.indexOf("let __hx_ordered_left") < 0)
			throw "Stage3 must bind effectful concatenation operands left to right";
		if (generated.indexOf("((\"[\") ^ (name))") < 0)
			throw "Stage3 added ordering bindings to a concatenation whose order cannot be observed";
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_CONCAT_ORDER_NATIVE:PASS");
	}
}
