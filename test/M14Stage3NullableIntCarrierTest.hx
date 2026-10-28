import sys.io.File;

/**
	Prove that nullable `Int` and `Float` values keep one native representation
	when they are assigned, compared, unwrapped for arithmetic, and returned.
	The fixture mirrors the version parser from the Stage3 end-to-end job whose
	mixed `Std.parseInt`/`0` ternary previously failed to compile as OCaml.
 */
class M14Stage3NullableIntCarrierTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_nullable_int_carrier";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_INT_CARRIER_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_nullable_int_carrier", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_INT_CARRIER_NATIVE:PASS");
	}
}
