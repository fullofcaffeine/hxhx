import sys.io.File;

/**
	Prove that recursive local functions build and run in the native OCaml
	program, as they do in Haxe 4.3.7.

	A named local function that calls itself, directly or from a nested closure,
	must be a recursive OCaml binding. Mutual recursion through a variable
	declared before both functions and a `var f = function ...` value that names
	an earlier `f` keep their non-recursive binding.

	The fixture first runs under upstream Haxe, so `expected.stdout` stays an
	upstream observation. The same source is then emitted through the native
	Stage3 OCaml emitter, built, and run; its output must match line for line.
 */
class M14Stage3LocalRecursiveFunctionsTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_local_recursive_functions";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		// HAXE_BIN lets a worktree without node_modules use another checkout's pinned Haxe.
		final haxe = Sys.getEnv("HAXE_BIN");
		M14Stage3RuntimeFixture.observe({
			command: haxe == null || haxe.length == 0 ? "node_modules/.bin/haxe" : haxe,
			arguments: ["-cp", root, "--run", "Main"],
			expected: expected
		});
		Sys.println("M14_STAGE3_LOCAL_RECURSIVE_FUNCTIONS_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_local_recursive_functions", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_LOCAL_RECURSIVE_FUNCTIONS_NATIVE:PASS");
	}
}
