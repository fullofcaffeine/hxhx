/** Preserve upstream-observed binary64 constants through production C++ emission. */
class M14CppFloatLiteralIntegrationTest {
	static function main():Void {
		final root = "test/oracle/cpp_float_literal_seed";
		final path = root + "/Main.hx";
		final parsed = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final module = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity();
		final directory = ".tmp/cpp-float-literals";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([module], false),
			new backend.BackendContext(directory, null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity() != revision)
			throw "Float literal emission did not preserve its authored source";
		execute(result.entryPath, [], "");
		final expected = sys.io.File.getContent(root + "/expected.bits.stdout");
		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/observer" + optimization.substr(1);
			if (Sys.command("c++", [
				"-std=c++17",
				optimization,
				"-Wall",
				"-Wextra",
				"-Werror",
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				"-I" + directory + "/src",
				root + "/Observe.cpp",
				"-o",
				executable
			]) != 0)
				throw "Float observer failed to compile";
			execute(executable, [], expected + expected);
			Sys.println("CPP_FLOAT_LITERAL:PASS " + optimization);
		}
	}

	/** A sanitizer warning or unexpected output is a failure even if the process exits zero. */
	static function execute(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || output != expected || errors != "")
			throw "Float literal bits differ from the independent contract: " + status + " " + output + errors;
	}
}
