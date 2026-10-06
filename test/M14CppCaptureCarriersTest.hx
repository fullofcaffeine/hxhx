import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Checks the real native carrier graph used by an escaped callback and its copied value. */
class M14CppCaptureCarriersTest {
	static function main():Void {
		final root = "test/oracle/source_capture_carriers_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final context = new BackendContext(".tmp/source-capture-carriers", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false), context);
		if (!result.builtExecutable)
			throw "capture carrier contract requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		sys.io.File.saveContent(".tmp/source-capture-carriers/actual.stdout", output);
		if (code != 0 || output != sys.io.File.getContent(root + "/expected.stdout"))
			throw "native capture carrier behavior differs: " + output + errors;
		Sys.println("CPP_CAPTURE_CARRIERS:PASS");
	}
}
