import sys.io.File;

/** Compare enum exception behavior with fixed expectations and upstream Haxe execution. */
class M14Stage3EnumExceptionTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_enum_exceptions";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_ENUM_EXCEPTION_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_enum_exceptions", true, true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_EXCEPTION_NATIVE:PASS");
	}
}
