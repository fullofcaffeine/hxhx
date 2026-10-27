import sys.FileSystem;
import sys.io.File;

/** Calls in a provided typed module retain their defaults without reparsing a source file. */
class M14Stage3VirtualOptionalCallsTest {
	static function main():Void {
		final fixture = "test/ocaml_optional_wrappers";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		final virtualPath = CompilerBundledSources.targetRoot("ocaml") + "/optional-wrapper-observer/Main.hx";
		if (FileSystem.exists(virtualPath))
			throw "optional wrapper observer requires a source path absent from disk";
		final typed = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(fixture + "/Main.hx"), path: virtualPath, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/m14_virtual_optional_calls", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_VIRTUAL_OPTIONAL_CALLS:PASS");
	}
}
