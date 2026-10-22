/** Standard conversion must preserve actual value tags across an authored Dynamic boundary. */
class M14CppStandardStringTest {
	static function main():Void {
		final root = "test/oracle/cpp_standard_string_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		observe(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]), expected, "upstream");
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Std", "Sys"]});
		final owner = fixture.index.getByFullName("Std");
		final declaration = owner.declarationForSignature(owner.staticMethod("string"));
		backend.cpp.CppManagedStandardString.requireDeclaration(declaration);
		final arguments = declaration.getSignature().getArgs();
		final original = arguments[0];
		arguments[0] = TyType.fromHintText("Int");
		var rejected = false;
		try {
			backend.cpp.CppManagedStandardString.requireDeclaration(declaration);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("one required Dynamic input") >= 0;
		}
		arguments[0] = original;
		if (!rejected)
			throw "standard conversion accepted a changed signature";
		final output = ".tmp/cpp-standard-string";
		// The real standard library contains private-access permissions. Consume
		// them through shared property lowering before projecting backend bodies.
		final lowered = TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index);
		backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(lowered, false),
			new backend.BackendContext(output, null, "Main", true, false, fixture.defines));
		Sys.println("CPP_STANDARD_STRING:emitted");
		sys.io.File.copy("test/cpp_managed_heap/StandardStringObserver.cpp", output + "/Observer.cpp");
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
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0)
				throw "standard conversion observer did not compile";
			observe(new sys.io.Process(timeout, ["30", executable]), expected, optimization);
			Sys.println("CPP_STANDARD_STRING:" + optimization + ":PASS");
		}
		Sys.println("CPP_STANDARD_STRING:PASS");
	}

	/** Compare exact output bytes as well as the observer's storage and sanitizer exit status. */
	static function observe(process:sys.io.Process, expected:String, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = try {
			process.exitCode();
		} catch (error:haxe.Exception) {
			process.close();
			throw new haxe.Exception(context + " failed: " + stderr, error);
		}
		process.close();
		if (code != 0 || stdout != expected)
			throw "standard conversion differs at " + context + ": " + stdout + stderr;
	}
}
