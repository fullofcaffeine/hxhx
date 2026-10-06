import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe late assignment and checked unassigned reads in emitted C++, including captured cells. */
class M14CppUninitializedLocalTest {
	static function exercise(moduleName:String, diagnostic:String):Void {
		final path = "test/oracle/cpp_uninitialized_local_seed/" + moduleName + ".hx";
		final output = ".tmp/cpp-uninitialized-local/" + moduleName;
		final module = new ResolvedModule(moduleName, path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		CppTargetCore.emit(new MacroExpandedProgram([typed], false), new BackendContext(output, null, moduleName, true, false, new haxe.ds.StringMap()));
		sys.io.File.copy("test/cpp_managed_heap/UninitializedLocalObserver.cpp", output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			final built = Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				'-DHXHX_LOCAL_PROGRAM="src/' + moduleName + '.cpp"',
				'-DHXHX_UNASSIGNED_DIAGNOSTIC="' + diagnostic + '"',
				output + "/Observer.cpp",
				"-o",
				executable
			]);
			if (built != 0)
				throw "local assignment observer compilation failed at " + optimization + " with exit " + built;
			final observed = Sys.command(timeout, ["30", executable]);
			if (observed != 0)
				throw "local assignment observer failed at " + optimization + " with exit " + observed;
			Sys.println("CPP_UNINITIALIZED_LOCAL:" + moduleName + ":" + optimization + ":PASS");
		}
	}

	static function main():Void {
		exercise("UninitializedLocals", "");
		exercise("UnassignedRead", "managed local slot is unassigned");
		exercise("CapturedUnassignedRead", "managed cell is unassigned");
		Sys.println("CPP_UNINITIALIZED_LOCAL:PASS");
	}
}
