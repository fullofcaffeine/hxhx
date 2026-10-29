import sys.io.File;

/** Compare real-provider native String field updates with independent upstream output. */
class M14OcamlStringFieldUpdateIntegrationTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_string_field_update";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("STRING_FIELD_UPDATE_UPSTREAM:PASS");
		final typed = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_string_field_update", true);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "String field lowering changed authored typed source";
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("STRING_FIELD_UPDATE_NATIVE:PASS");
	}
}
