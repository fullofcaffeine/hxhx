import sys.io.File;

/** Prove that deep ordinary arithmetic remains practical and preserves native results and effects. */
class M14NestedArithmeticEmissionTest {
	static function main():Void {
		final root = "test/fixtures/nested_arithmetic_emission";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("NESTED_ARITHMETIC_UPSTREAM:PASS");
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/nested_arithmetic_emission");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("NESTED_ARITHMETIC_NATIVE:PASS");
	}
}
