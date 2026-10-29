import sys.io.File;

/** Execute the same enum equality operation through upstream Haxe and the native OCaml compiler path. */
class M14Stage3EnumEqualityTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_enum_equality";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_ENUM_EQUALITY_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_enum_equality", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_EQUALITY_NATIVE:PASS");
	}
}
