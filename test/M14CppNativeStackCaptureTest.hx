/** Prove the real native stack declaration through ordinary generated C++ and collection. */
class M14CppNativeStackCaptureTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/fixtures/cpp_native_stack_capture_seed",
			mainModule: "Main",
			requiredModules: ["haxe.NativeStackTrace", "Any"]
		});
		final stackOwner = fixture.index.getByFullName("haxe.NativeStackTrace");
		final declaration = stackOwner.declarationForSignature(stackOwner.staticMethod("callStack"));
		backend.cpp.CppManagedNativeStack.requireDeclaration(declaration);
		final localOwner = fixture.index.getByFullName("Main");
		if (backend.cpp.CppManagedNativeStack.owns(localOwner.declarationForSignature(localOwner.staticMethod("callStack"))))
			throw "stack binding selected a same-named authored method";
		final arguments = declaration.getSignature().getArgs();
		arguments.push(TyType.fromHintText("Int"));
		var rejected = false;
		try {
			backend.cpp.CppManagedNativeStack.requireDeclaration(declaration);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("no parameters") >= 0;
		}
		arguments.pop();
		if (!rejected)
			throw "stack binding accepted a mutated signature";
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (debug in [false, true]) {
			final output = ".tmp/cpp-native-stack-capture/" + (debug ? "debug" : "release");
			final defines = fixture.defines.copy();
			if (debug)
				defines.set("debug", "1");
			final result = backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, "Main", true, true, defines));
			if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
				throw "native stack capture failed ordinary execution";
			sys.io.File.copy("test/cpp_managed_heap/NativeStackCaptureObserver.cpp", output + "/Observer.cpp");
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
					throw "native stack capture failed its collecting observer";
				Sys.println("CPP_NATIVE_STACK_CAPTURE:" + (debug ? "debug" : "release") + ":" + optimization + ":PASS");
			}
		}
	}
}
