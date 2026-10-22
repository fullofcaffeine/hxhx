import sys.io.File;

/** Compare real-provider native generic argument and result conversions with independent upstream output. */
class M14OcamlGenericValuesIntegrationTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_generic_values";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("GENERIC_VALUES_UPSTREAM:PASS");
		final typed = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/ocaml_generic_values", true, true);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "Generic representation selection changed authored typed source";
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("GENERIC_VALUES_NATIVE:PASS");
	}
}
