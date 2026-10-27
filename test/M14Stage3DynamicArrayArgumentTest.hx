import sys.io.File;

/** Compare erased array arguments and shared mutations with upstream Haxe. */
class M14Stage3DynamicArrayArgumentTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_dynamic_array_argument";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_DYNAMIC_ARRAY_ARGUMENT_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_dynamic_array_argument", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_DYNAMIC_ARRAY_ARGUMENT_NATIVE:PASS");
	}
}
