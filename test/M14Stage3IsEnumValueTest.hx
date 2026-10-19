import sys.io.File;

/** Execute the same enum-value predicate through upstream Haxe and the native OCaml compiler path. */
class M14Stage3IsEnumValueTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_is_enum_value";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_IS_ENUM_VALUE_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_is_enum_value", true, true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_IS_ENUM_VALUE_NATIVE:PASS");
	}
}
