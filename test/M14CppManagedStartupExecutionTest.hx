import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe the normal generated program runner, including unused-class effects and per-heap startup. */
class M14CppManagedStartupExecutionTest {
	static function main():Void {
		runFixture({
			sourceRoot: "test/fixtures/cpp_managed_startup_execution_seed",
			output: ".tmp/managed-startup-execution",
			observer: "test/cpp_managed_heap/StartupObserver.cpp"
		});
		runFixture({
			sourceRoot: "test/fixtures/cpp_managed_startup_throw_seed",
			output: ".tmp/managed-startup-throw",
			observer: "test/cpp_managed_heap/StartupThrowObserver.cpp"
		});
		Sys.println("CPP_MANAGED_STARTUP_EXECUTION:PASS");
	}

	/** Execute the normal program runner with a separate observer; never rewrite its generated source. */
	public static function runFixture(input:{
		sourceRoot:String,
		output:String,
		observer:String,
		?requiredModules:Array<String>
	}):Void {
		final fixture = input.requiredModules == null ? null : CppResolvedFixture.load({
			sourceRoot: input.sourceRoot,
			mainModule: "Main",
			requiredModules: input.requiredModules
		});
		final modules = if (fixture == null) {
			final source = sys.io.File.getContent(input.sourceRoot + "/Main.hx");
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			[TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))];
		} else fixture.modules;
		final program = new MacroExpandedProgram(modules, false);
		final output = input.output;
		CppTargetCore.emit(program,
			new BackendContext(output, output + "/Main.cpp", "Main", true, false, fixture == null ? new haxe.ds.StringMap() : fixture.defines));
		sys.io.File.copy(input.observer, output + "/Observer.cpp");
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
			if (code != 0 || stderr.length != 0 || stdout != sys.io.File.getContent(input.sourceRoot + "/expected.stdout"))
				throw "startup observation failed: " + stdout + stderr;
		}
	}
}
