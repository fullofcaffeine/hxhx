import sys.io.File;

/**
	Compare a native Stage3 program with upstream Haxe 4.3.7 for the fixture
	test/fixtures/ocaml_local_function_reference_results.

	The fixture first runs under upstream Haxe, so `expected.stdout` stays an
	upstream observation. The same source is then emitted through the native
	Stage3 OCaml emitter, built, and run; its output must match line for line.
 */
class M14Stage3LocalFunctionReferenceResultsTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_local_function_reference_results";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		// HAXE_BIN lets a worktree without node_modules use another checkout's pinned Haxe.
		final haxe = Sys.getEnv("HAXE_BIN");
		M14Stage3RuntimeFixture.observe({
			command: haxe == null || haxe.length == 0 ? "node_modules/.bin/haxe" : haxe,
			arguments: ["-cp", root, "--run", "Main"],
			expected: expected
		});
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_REFERENCE_RESULTS_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_local_function_reference_results", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_REFERENCE_RESULTS_NATIVE:PASS");
		requireUnsupportedEmitFailure(root);
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_REFERENCE_RESULTS_UNSUPPORTED:PASS");
	}

	/**
		An abstract result is stored as its backing value, not as a reference, so
		it must still stop emission (haxe_ocaml-2ir3k). Upstream Haxe prints 7.
	 */
	static function requireUnsupportedEmitFailure(root:String):Void {
		final source = "abstract Id(Int) { public function new(v:Int) this = v; public function get():Int return this; }\n"
			+ "class Main { static function main():Void { function make(v:Int):Id { return new Id(v); } Sys.println(make(7).get()); } }";
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_local_function_reference_results_unsupported", true);
			null;
		} catch (error:String) {
			error;
		}
		if (message == null || message.indexOf("OCaml block function requires a supported concrete return carrier") < 0)
			throw "an abstract block-function result must fail at emit time, got: " + message;
	}
}
