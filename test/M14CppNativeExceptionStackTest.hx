/** Check generated throw boundaries and the real exceptionStack API with native catch observers. */
class M14CppNativeExceptionStackTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/fixtures/cpp_native_stack_capture_seed",
			mainModule: "ExceptionMain",
			requiredModules: ["haxe.NativeStackTrace", "Any"]
		});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final owner = fixture.index.getByFullName("ExceptionMain");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (debug in [false, true]) {
			final output = ".tmp/cpp-native-exception-stack/" + (debug ? "debug" : "release");
			final defines = fixture.defines.copy();
			if (debug)
				defines.set("debug", "1");
			final result = backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, "ExceptionMain", true, true, defines));
			if (!result.builtExecutable)
				throw "exception stack fixture did not produce its native program";
			// Resolve the host observer's two entry points through the same exact
			// declaration plan. The test never parses or guesses generated symbol names.
			final plan = new backend.cpp.CppManagedProgramPlan(new backend.cpp.CppTypedProgramProjection(program), "ExceptionMain", debug);
			final bindings = new Array<String>();
			for (binding in [
				{name: "observe", macroName: "HXHX_OBSERVE_STACK"},
				{name: "secondary", macroName: "HXHX_SECOND_THROW"}
			]) {
				final identity = owner.declarationForSignature(owner.staticMethod(binding.name)).getIdentity().getCanonicalKey();
				final target = @:privateAccess plan.emitter.resolve(identity);
				bindings.push("#define " + binding.macroName + " " + backend.cpp.CppManagedStaticTarget.sourceSymbol(target));
			}
			sys.io.File.saveContent(output + "/Bindings.hpp", bindings.join("\n") + "\n");
			sys.io.File.copy("test/cpp_managed_heap/NativeExceptionStackObserver.cpp", output + "/Observer.cpp");
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
					"-DHXHX_EXPECT_STACK=" + (debug ? "1" : "0"),
					output + "/Observer.cpp",
					"-o",
					executable
				]) != 0 || Sys.command(timeout, ["30", executable]) != 0)
					throw "generated exception stack observer failed";
				Sys.println("CPP_NATIVE_EXCEPTION_STACK:" + (debug ? "debug" : "release") + ":" + optimization + ":PASS");
			}
		}
	}
}
