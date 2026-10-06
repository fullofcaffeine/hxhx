/** Native assertion fixtures with only scalar static storage must release every temporary allocation. */
class CppManagedAssertionFixture {
	/** Compile both sanitizer profiles; the selected observer must force collection and check temporary-root cleanup. */
	public static function sanitizers(output:String, label:String, observerSource:String = "test/cpp_managed_heap/UninitializedLocalObserver.cpp"):Void {
		sys.io.File.copy(observerSource, output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			if (Sys.command(timeout, [
				"90",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				'-DHXHX_UNASSIGNED_DIAGNOSTIC=""',
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0)
				throw label + ": sanitizer compilation failed";
			if (Sys.command(timeout, ["30", executable]) != 0)
				throw label + ": sanitizer assertions failed";
			Sys.println(label + ":" + optimization + ":PASS");
		}
	}
}
