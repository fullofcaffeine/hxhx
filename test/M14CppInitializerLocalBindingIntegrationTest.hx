import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native initialization must preserve separate initializer and constructor bindings. */
class M14CppInitializerLocalBindingIntegrationTest {
	/** The regular C++ smoke test also requires this native observer. */
	public static function run():Void {
		final root = "test/oracle/cpp_initializer_local_binding_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([typed], false);
		final context = new BackendContext(".tmp/cpp-initializer-local-bindings", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "C++ initializer binding test requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "C++ initializer binding behavior differs: " + stdout + stderr;
		Sys.println("CPP_INITIALIZER_LOCAL_BINDING_NATIVE:PASS");
	}

	static function main():Void
		run();
}
