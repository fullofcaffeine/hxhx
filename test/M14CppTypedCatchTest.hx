import backend.BackendContext;
import backend.cpp.CppTargetCore;

/**
	Require the native compiler to preserve thrown values, ordered handlers, and escaped catch variables.
	The expected output is independently checked with upstream Haxe eval, Neko, and C++.
	This test must remain red until the complete fixture executes through the candidate target.
**/
class M14CppTypedCatchTest {
	public static function run():Void {
		M14CppCatchUseTest.run();
		runProgram("Main", "expected.stdout", ["haxe.Exception", "haxe.ValueException"]);
		runProgram("NumericCatchMain", "numeric.cpp.stdout", []);
		runProgram("WrapperCatchMain", "wrapper.cpp.stdout", ["haxe.Exception", "haxe.ValueException"]);
		runProgram("RuntimeBoundaryCatchMain", "runtime-boundary.expected.stdout", ["haxe.io.Eof"]);
		M14CppInitializerCatchExecutionTest.run();
	}

	/** Use the production classpath and lazy-loading boundaries so real standard-library declarations participate. */
	static function runProgram(mainModule:String, expectedFile:String, requiredModules:Array<String>):Void {
		final root = "test/oracle/cpp_typed_catch_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root + "/src", mainModule: mainModule, requiredModules: requiredModules});
		final typed = fixture.modules;
		final functions = [
			for (module in typed)
				for (typedClass in module.getTypedClasses())
					for (fn in typedClass.getFunctions())
						fn
		];
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final outputDirectory = ".tmp/cpp-typed-catch-candidate/" + mainModule;
		final context = new BackendContext(outputDirectory, null, mainModule, true, true, fixture.defines);
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, fixture.index), false);
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "typed catch contract requires a native executable";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "typed catch emission changed the original typed function";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		sys.io.File.saveContent(outputDirectory + "/actual.stdout", stdout);
		sys.io.File.saveContent(outputDirectory + "/actual.stderr", stderr);
		if (code != 0 || stdout != sys.io.File.getContent(root + "/" + expectedFile))
			throw "native typed catch behavior differs from upstream: " + stdout + stderr;
		Sys.println("CPP_TYPED_CATCH_NATIVE:PASS " + mainModule);
	}

	static function main():Void
		run();
}
