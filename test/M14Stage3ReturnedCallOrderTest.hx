import sys.io.File;

/** Compare returned-callable arity, local shadowing, and effects with upstream Haxe. */
class M14Stage3ReturnedCallOrderTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_returned_call_order";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_RETURNED_CALL_ORDER_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_returned_call_order", true, true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_RETURNED_CALL_ORDER_NATIVE:PASS");
	}
}
