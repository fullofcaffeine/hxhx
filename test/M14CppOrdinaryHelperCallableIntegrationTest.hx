import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compile and execute helper calls against independently authored source behavior. */
class M14CppOrdinaryHelperCallableIntegrationTest {
	public static function run():Void {
		final root = "test/oracle/cpp_ordinary_helper_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([typed], false);
		final context = new BackendContext(".tmp/cpp-ordinary-helper-callable", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Helper callable observer requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Helper callable behavior differs: " + stdout + stderr;
		Sys.println("CPP_ORDINARY_HELPER_CALLABLE_NATIVE:PASS");
	}

	static function main():Void
		run();
}
