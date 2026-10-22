import backend.cpp.CppTypedProgramProjection;

/** Shared overload selection and retained slots must agree on optional skipping. */
class M14ConstructorOptionalSkipTest {
	static function main():Void {
		final root = "test/oracle/constructor_optional_skip_seed";
		final overrideCompiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final compiler = overrideCompiler == null ? "node_modules/.bin/haxe" : overrideCompiler;
		final child = new sys.io.Process(compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final output = child.stdout.readAll().toString();
		final errors = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		final expected = "selected\nsupplied\n1\n";
		if (code != 0 || errors != "" || output != expected)
			throw "upstream optional skipping differs: " + output + errors;
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final main = program.requireClass(program.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		final entries = main.getConstructorCatalog().getEntries();
		if (entries.length != 2)
			throw "optional skipping lost a source call";
		final slots = entries[0].requireArgumentBinding().getSlots();
		if (slots.length != 2 || !slots[0].match(Omitted) || !slots[1].match(Supplied(0)))
			throw "optional skipping assigned the source argument to another slot";
		if (entries[0].getArguments().length != 1)
			throw "source projection inserted an authored operand";
		switch entries[0].getExpression() {
			case ENew(_, arguments):
				if (arguments.length != 2 || !arguments[0].match(ENull) || arguments[1] != entries[0].getArguments()[0])
					throw "constructor projection changed the supplied effect";
			case _:
				throw "fixture lost its constructor projection";
		}
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		// Native output requires the real Sys declaration. Use production loading
		// rather than treating its unresolved name as a local callable.
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Sys"]});
		final nativeProgram = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = backend.cpp.CppTargetCore.emit(nativeProgram,
			new backend.BackendContext(".tmp/cpp-constructor-optional-skip", null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "optional skipping requires a native executable";
		final native = new sys.io.Process(result.entryPath, []);
		final nativeOutput = native.stdout.readAll().toString();
		final nativeErrors = native.stderr.readAll().toString();
		final nativeCode = native.exitCode();
		native.close();
		if (nativeCode != 0 || nativeErrors != "" || nativeOutput != expected)
			throw "native optional skipping differs: " + nativeOutput + nativeErrors;
		sanitizers();
		Sys.println("CONSTRUCTOR_OPTIONAL_SKIP:PASS");
	}

	/** Re-enter this exact generated program with collection before every allocation. */
	public static function sanitizers():Void {
		final output = ".tmp/cpp-constructor-optional-skip";
		// Production loading retains the reviewed standard-library inventory: one
		// storage object, six enum singletons, and one StringTools character array.
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
				throw "optional constructor sanitizer observer did not compile";
			final child = new sys.io.Process(timeout, ["30", executable]);
			final stdout = child.stdout.readAll().toString();
			final stderr = child.stderr.readAll().toString();
			final code = try child.exitCode() catch (failure:haxe.Exception) {
				child.close();
				throw "optional constructor observer terminated: " + stdout + stderr + failure.message;
			};
			child.close();
			if (code != 0 || stderr != "" || stdout != "selected\nsupplied\n1\n")
				throw "optional constructor sanitizer observer differs: " + stdout + stderr;
			Sys.println("CONSTRUCTOR_OPTIONAL_SKIP:" + optimization + ":SANITIZERS_PASS");
		}
	}
}
