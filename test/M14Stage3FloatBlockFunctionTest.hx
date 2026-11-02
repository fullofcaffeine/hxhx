import sys.io.File;

/**
	Prove that block-bodied local functions and function expressions declared
	to return `Float` run in the native OCaml program as they do in Haxe 4.3.7.
	The emitter chooses the OCaml `float` result carrier from the typed return
	type, so literal, local, arithmetic and multi-return results all work,
	including a closure that updates a captured outer `Float` local.

	The fixture first runs under upstream Haxe, so `expected.stdout` stays an
	upstream observation. The same source is then emitted through the native
	Stage3 OCaml emitter, built, and run; its output must match line for line.
 */
class M14Stage3FloatBlockFunctionTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_float_block_function";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_FLOAT_BLOCK_FUNCTION_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_float_block_function", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_FLOAT_BLOCK_FUNCTION_NATIVE:PASS");
		requireUnsupportedEmitFailure(root);
		Sys.println("M14_STAGE3_FLOAT_BLOCK_FUNCTION_UNSUPPORTED:PASS");
	}

	/**
		A `Dynamic` value returned from a `Float` function needs a checked
		extraction that the native emitter does not model yet. Emission must stop
		with a named error instead of reading the boxed value as a float.
		Upstream Haxe prints 0.25 for this program.
	 */
	static function requireUnsupportedEmitFailure(root:String):Void {
		final source = "class Main { static function main():Void { var d:Dynamic = 0.25; final read = function():Float { return d; }; Sys.println(read()); } }";
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_float_block_function_unsupported", true);
			null;
		} catch (error:String) {
			error;
		}
		if (message == null || message.indexOf("unsupported OCaml block return representation conversion") < 0)
			throw "a Dynamic result in a Float block function must fail at emit time, got: " + message;
	}
}
