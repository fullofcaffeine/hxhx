import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe named-function capture, recursion, and escaped lifetime through the native target. */
class M14SourceNamedFunctionTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/source_named_function_seed/src",
			mainModule: "Main",
			requiredModules: ["Array", "Sys"]
		});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final context = new BackendContext(".tmp/source-named-function", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false), context);
		if (!result.builtExecutable)
			throw "named function requires a native executable";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "named-function lowering changed the original typed source";
		observe(result.entryPath);
		final sources = [
			for (artifact in result.artifacts)
				if (artifact.kind == "entry_cpp_source") artifact.path
		];
		if (sources.length != 1 || [
			for (artifact in result.artifacts)
				if (artifact.kind == "cpp_managed_runtime_header") artifact
		].length != 4)
			throw "normal C++ target lost its source or managed runtime publication";
		final source = sys.io.File.getContent(sources[0]);
		if (source.indexOf("std::function") >= 0 || source.indexOf("std::shared_ptr") >= 0)
			throw "normal counter retained an old owning carrier";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final selectedCompiler = Sys.getEnv("CXX");
		final compiler = selectedCompiler == null ? "clang++" : selectedCompiler;
		for (optimization in ["-O0", "-O2"]) {
			final executable = context.outputDir + "/sanitized" + optimization;
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
				sources[0],
				"-o",
				executable
			]) != 0)
				throw "normal counter failed strict sanitized compilation";
			observe(executable);
		}
		Sys.println("SOURCE_NAMED_FUNCTION_NATIVE:PASS");
	}

	/** Compare the unchanged source expectation for normal and sanitizer-built executables. */
	static function observe(executable:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", executable]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stderr.length != 0 || stdout != sys.io.File.getContent("test/oracle/source_named_function_seed/expected.stdout"))
			throw "named-function binding or lifetime changed observed behavior: " + stdout + stderr;
	}

	static function main():Void
		run();
}
