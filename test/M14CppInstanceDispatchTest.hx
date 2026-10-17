import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** The same authored assertions must pass upstream and through ordinary managed class dispatch. */
class M14CppInstanceDispatchTest {
	static function main():Void {
		final root = "test/oracle/cpp_instance_dispatch_seed";
		observe(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]), "upstream");
		Sys.println("CPP_INSTANCE_DISPATCH_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		// All nominal types in this reduction are authored in Main; no standard
		// Array, Sys, exception provider, or other external class is required.
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/cpp-instance-dispatch", null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "ordinary instance dispatch requires a native executable";
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "instance dispatch changed the typed source";
		observe(new sys.io.Process(result.entryPath, []), "native");
		Sys.println("CPP_INSTANCE_DISPATCH_NATIVE:PASS");
		final output = ".tmp/cpp-instance-dispatch";
		sys.io.File.copy("test/cpp_managed_heap/InstanceDispatchObserver.cpp", output + "/Observer.cpp");
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
			Sys.println("CPP_INSTANCE_DISPATCH:" + optimization + ":PASS");
		}
		Sys.println("CPP_INSTANCE_DISPATCH:PASS");
	}

	/** Every source assertion is mandatory; successful execution has no output. */
	static function observe(process:sys.io.Process, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw context + " instance dispatch differs (exit " + code + "): " + stdout + stderr;
	}
}
