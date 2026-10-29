import sys.io.File;

/**
	Prove that increments, decrements, and compound assignments on nullable Int
	and Float locals keep the native nullable carrier intact.

	A postfix update must produce the old number, a prefix update the new one,
	and the stored value must stay in the carrier. Updating a null value must
	throw before it stores anything, instead of doing arithmetic on the null
	sentinel's bits. Nested `Null<Null<Int>>` locals type and run like one
	nullable layer, as they do in Haxe 4.3.7.
 */
class M14Stage3NullableLocalUpdateTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_nullable_local_update";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_LOCAL_UPDATE_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_nullable_local_update", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_NULLABLE_LOCAL_UPDATE_NATIVE:PASS");
	}
}
