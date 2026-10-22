import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe the normal generated program runner, including enum identity, startup ordering, and per-heap storage. */
class M14CppManagedEnumSingletonTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/cpp_managed_enum_singleton_seed/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final program = new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], false);
		final output = ".tmp/managed-enum-singleton";
		CppTargetCore.emit(program, new BackendContext(output, output + "/Main.cpp", "Main", true, false, new haxe.ds.StringMap()));
		sys.io.File.copy("test/cpp_managed_heap/EnumSingletonObserver.cpp", output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final binary = output + "/test" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				"-Wall",
				"-Wextra",
				"-Werror",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-I",
				output,
				output + "/Observer.cpp",
				"-o",
				binary
			]) != 0)
				throw "startup observer failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0
				|| stderr.length != 0
				|| stdout != sys.io.File.getContent("test/fixtures/cpp_managed_enum_singleton_seed/expected.stdout"))
				throw "startup observation failed: " + stdout + stderr;
		}
		Sys.println("CPP_MANAGED_ENUM_SINGLETON_STARTUP:PASS");
	}
}
