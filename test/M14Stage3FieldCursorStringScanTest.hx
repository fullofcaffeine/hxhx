import sys.io.File;

/**
	Run a field-cursor string scanner natively and compare it with upstream.
	The OCaml `Xml` parser keeps its position in an Int instance field and reads
	characters from a String field. Native lowering used to emit a placeholder
	for `field += n` (only `++` and String `+=` were lowered), so the cursor
	never moved, and it sent `charAt` to the empty String stub, which crashed.
 */
class M14Stage3FieldCursorStringScanTest {
	static function main():Void {
		final root = "test/fixtures/stage3_field_cursor_string_scan";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_FIELD_CURSOR_STRING_SCAN_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3_field_cursor_string_scan", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_FIELD_CURSOR_STRING_SCAN_NATIVE:PASS");
	}
}
