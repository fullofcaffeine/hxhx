import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare authored stored methods with upstream, then observe native execution and collecting heaps. */
class M14CppBoundCallableIntegrationTest {
	static function main():Void {
		final root = "test/fixtures/cpp_bound_callable";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final started = haxe.Timer.stamp();
		execute("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], sys.io.File.getContent(root + "/expected.eval.stdout"));
		Sys.println("CPP_BOUND_CALLABLE:UPSTREAM_EVAL " + (haxe.Timer.stamp() - started));
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Main"]});
		Sys.println("CPP_BOUND_CALLABLE:PROVIDERS_LOADED " + (haxe.Timer.stamp() - started));
		final directory = ".tmp/cpp-bound-callable";
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), new BackendContext(directory, null, "Main", true, fixture.defines));
		if (!result.builtExecutable)
			throw "Stored method fixture did not build its native executable";
		execute(result.entryPath, [], expected);
		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/stress" + optimization.substr(1);
			if (Sys.command("c++", [
				"-std=c++17",
				optimization,
				"-Wall",
				"-Wextra",
				"-Werror",
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-I" + directory + "/src",
				root + "/Stress.cpp",
				"-o",
				executable
			]) != 0)
				throw "Stored method collection observer failed to compile: " + optimization;
			execute(executable, [], expected + expected);
			Sys.println("CPP_BOUND_CALLABLE:PASS " + optimization);
		}
	}

	/** Capture the real process result; compile success alone cannot prove receiver or lifetime behavior. */
	static function execute(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected || errors != "")
			throw "Stored method execution differs from its contract: " + code + " " + output + errors;
	}
}
