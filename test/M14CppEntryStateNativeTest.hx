import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare entry-class storage, initialization order, and shadowing with upstream behavior. */
class M14CppEntryStateNativeTest {
	static function main():Void {
		final root = "test/oracle/cpp_entry_state_seed";
		final path = root + "/src/EntryStateMain.hx";
		final resolved = new ResolvedModule("EntryStateMain", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final context = new BackendContext(".tmp/cpp-entry-state", null, "EntryStateMain", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false), context);
		if (!result.builtExecutable)
			throw "entry storage regression requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "entry-class behavior differs: " + stdout + stderr;
		Sys.println("CPP_ENTRY_STATE_NATIVE:PASS");
	}
}
