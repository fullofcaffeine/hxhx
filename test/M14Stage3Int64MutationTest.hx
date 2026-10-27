import sys.io.File;

/** Prove in-place Int64 word mutation, alias sharing, and copy independence natively. */
class M14Stage3Int64MutationTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_int64_mutation";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_INT64_MUTATION_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_int64_mutation", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_INT64_MUTATION_NATIVE:PASS");
	}
}
