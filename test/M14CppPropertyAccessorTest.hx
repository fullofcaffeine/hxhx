import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe property semantics through upstream execution and the native target. */
class M14CppPropertyAccessorTest {
	static function main():Void {
		final root = "test/oracle/cpp_property_accessor_seed";
		observe(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]), "upstream");
		Sys.println("CPP_PROPERTY_ACCESSOR_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		// The reduction defines every nominal class locally, so a missing standard
		// library provider cannot explain a property selection or storage failure.
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/cpp-property-accessor", null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "property regression requires a native executable";
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "property emission changed the typed source";
		observe(new sys.io.Process(result.entryPath, []), "native");
		Sys.println("CPP_PROPERTY_ACCESSOR_NATIVE:PASS");
		final output = ".tmp/cpp-property-accessor";
		sys.io.File.copy("test/cpp_managed_heap/PropertyAccessorObserver.cpp", output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			observe(new sys.io.Process(timeout, [
				"60",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				output + "/Observer.cpp",
				"-o",
				executable
			]), "observer compile " + optimization);
			observe(new sys.io.Process(timeout, ["30", executable]), "observer run " + optimization);
			Sys.println("CPP_PROPERTY_ACCESSOR:" + optimization + ":PASS");
		}
		Sys.println("CPP_PROPERTY_ACCESSOR:PASS");
	}

	/** Assertions are mandatory; each successful program has empty stdout and stderr. */
	static function observe(process:sys.io.Process, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw context + " property assertions differ (exit " + code + "): " + stdout + stderr;
	}
}
