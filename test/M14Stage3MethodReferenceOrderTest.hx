import sys.io.File;

/**
	Prove that methods of one class can refer to each other in any declaration
	order once the native OCaml emitter splits them into separate bindings.
	OCaml only sees a binding that is defined earlier or in the same recursive
	group, so the emitter must count first-class method captures (including
	captures that inline lowering moved into a `map` loop) as dependencies, as
	it already does for direct calls. The fixture covers a capture of a later and
	an earlier instance method, two mutually recursive instance methods, and a
	capture of a later static method.
 */
class M14Stage3MethodReferenceOrderTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_method_reference_order";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_METHOD_REFERENCE_ORDER_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_method_reference_order", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_METHOD_REFERENCE_ORDER_NATIVE:PASS");
	}
}
