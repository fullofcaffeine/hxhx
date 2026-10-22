/** A defaulted arrow must preserve its entry value independently of later parameter reads and writes. */
class M14SourceArrowParameterEntryTest {
	public static function run(moduleName:String):Void {
		final path = "test/oracle/source_arrow_return_seed/" + moduleName + ".hx";
		final module = new ResolvedModule(moduleName, path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		typed.getBackendDeclaration();
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(".tmp/source-arrow-parameter-cases/" + moduleName, null, moduleName, true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "arrow parameter entry requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw "arrow parameter entry failed: " + stdout + stderr;
		final output = ".tmp/source-arrow-parameter-cases/" + moduleName;
		sys.io.File.copy("test/cpp_managed_heap/UninitializedLocalObserver.cpp", output + "/Observer.cpp");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				'-DHXHX_LOCAL_PROGRAM="src/' + moduleName + '.cpp"',
				'-DHXHX_UNASSIGNED_DIAGNOSTIC=""',
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0)
				throw "default parameter observer did not compile";
			if (Sys.command(timeout, ["30", executable]) != 0)
				throw "default parameter observer failed";
			Sys.println("SOURCE_ARROW_PARAMETER_ENTRY:" + moduleName + ":" + optimization + ":PASS");
		}
		Sys.println("SOURCE_ARROW_PARAMETER_ENTRY:" + moduleName + ":PASS");
	}

	static function main():Void {
		run("ArrowDefaults");
	}
}
