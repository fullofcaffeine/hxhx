import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe inherited fields and constructor effects in the unchanged authored program. */
class M14CppInheritedStorageTest {
	static function main():Void {
		exercise("Main", ".tmp/cpp-inherited-storage");
		Sys.println("CPP_INHERITED_STORAGE:PASS");
	}

	/** Separate authored programs share the same native execution and collection observer. */
	public static function exercise(moduleName:String, output:String):Void {
		final path = "test/oracle/cpp_inherited_storage_seed/" + moduleName + ".hx";
		final module = new ResolvedModule(moduleName, path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(output, null, moduleName, true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "inherited storage requires native execution";
		final child = new sys.io.Process(result.entryPath, []);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = try child.exitCode() catch (failure:haxe.Exception) {
			child.close();
			throw "inherited storage terminated abnormally: " + stdout + stderr + failure.message;
		};
		child.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw "inherited storage assertions failed: " + stdout + stderr;
		// Re-enter the emitted program with collection before every allocation.
		sys.io.File.copy("test/cpp_managed_heap/InheritedStorageObserver.cpp", output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
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
				'-DHXHX_INHERITED_PROGRAM="src/' + moduleName + '.cpp"',
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0 || Sys.command(timeout, ["30", executable]) != 0)
				throw "inherited storage sanitizer observer failed";
			Sys.println("CPP_INHERITED_STORAGE:" + optimization + ":PASS");
		}
	}
}
