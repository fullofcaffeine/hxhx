import sys.io.File;

/**
	Prove that a local compound assignment used as a value, such as
	`var r = (x -= 2)`, stores the update and produces the updated value in the
	native OCaml program, as it does in Haxe 4.3.7.

	The fixture first runs under upstream Haxe, so `expected.stdout` stays an
	upstream observation. The same source is then emitted through the native
	Stage3 OCaml emitter, built, and run; its output must match line for line.
 */
class M14Stage3LocalCompoundValueTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_local_compound_value";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_LOCAL_COMPOUND_VALUE_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_local_compound_value", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_LOCAL_COMPOUND_VALUE_NATIVE:PASS");
		requireUnsupportedEmitFailure(root);
		Sys.println("M14_STAGE3_LOCAL_COMPOUND_VALUE_UNSUPPORTED:PASS");
	}

	/**
		A local compound value whose representation the native emitter does not
		model must stop emission instead of producing a placeholder number.
		`Null<String>` has no native nullable String carrier for `+=` yet; upstream
		Haxe prints "ab" for this program.
	 */
	static function requireUnsupportedEmitFailure(root:String):Void {
		final source = "class Main { static function main():Void { var text:Null<String> = \"a\"; final appended = (text += \"b\"); Sys.println(appended); } }";
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_local_compound_value_unsupported", true);
			null;
		} catch (error:String) {
			error;
		}
		if (message == null || message.indexOf("unsupported OCaml local compound assignment value: += on Null<String>") < 0)
			throw "unsupported local compound value must fail at emit time, got: " + message;
	}
}
