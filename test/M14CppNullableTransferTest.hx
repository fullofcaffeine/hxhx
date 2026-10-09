import backend.cpp.CppManagedValueTransfer.accepts;
import backend.cpp.CppManagedValueTransfer.supports;
import backend.cpp.CppManagedValueTransfer.convertRoot;

/** Compare authored scalar transfer assertions with a collecting native runtime. */
class M14CppNullableTransferTest {
	/** A native scalar conversion must remain distinct from copying a nullable value. */
	static function admission():Void {
		final integer = TyType.fromHintText("Int");
		final nullable = TyType.nullable(integer);
		if (accepts(integer, nullable) || !supports(integer, nullable))
			throw "integer conversion admission differs";
		if (!accepts(nullable, nullable) || convertRoot(nullable, nullable, "root", "").length != 0)
			throw "nullable copy changed absence";
		for (source in [
			TyType.fromHintText("Dynamic"),
			TyType.fromHintText("String"),
			TyType.nullable(TyType.fromHintText("Bool"))
		])
			if (supports(integer, source))
				throw "unrelated integer conversion admitted";
		if (supports(TyType.fromHintText("Bool"), TyType.nullable(TyType.fromHintText("Bool"))))
			throw "Boolean conversion admitted without its own contract";
	}

	static function main():Void {
		admission();
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_nullable_transfer_seed", mainModule: "Main", requiredModules: ["Array"]});
		final modules = TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index);
		final output = ".tmp/cpp-nullable-transfer";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(modules, false),
			new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "nullable transfer assertions failed";
		sanitizers();
		Sys.println("CPP_NULLABLE_TRANSFER:PASS");
	}

	/** Force collection at each allocation; only the program's scalar static storage may survive. */
	public static function sanitizers():Void {
		final output = ".tmp/cpp-nullable-transfer";
		sys.io.File.copy("test/cpp_managed_heap/UninitializedLocalObserver.cpp", output + "/Observer.cpp");
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
				throw "nullable transfer sanitizer compilation failed";
			if (Sys.command(timeout, ["30", executable]) != 0)
				throw "nullable transfer sanitizer assertions failed";
			Sys.println("CPP_NULLABLE_TRANSFER:" + optimization + ":PASS");
		}
	}
}
