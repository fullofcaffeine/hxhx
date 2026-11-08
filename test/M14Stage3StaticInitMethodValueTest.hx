import sys.io.File;

/**
	Prove that a `static final` initializer can reach later helper methods
	through first-class method values in the native OCaml output.
	The emitter writes the helpers a static initializer needs into a prelude
	group before the static values, because OCaml only sees earlier bindings.
	That selection must follow method values (`map(shout)`, `final f = quote`,
	`static final g = bang`) as well as direct calls, or the generated module
	fails with `Unbound value`.
 */
class M14Stage3StaticInitMethodValueTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_static_init_method_value";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_STATIC_INIT_METHOD_VALUE_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_static_init_method_value", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_STATIC_INIT_METHOD_VALUE_NATIVE:PASS");
	}
}
