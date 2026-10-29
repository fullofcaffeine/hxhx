import backend.cpp.CppManagedValueTransfer.accepts;
import backend.cpp.CppManagedValueTransfer.supports;
import backend.cpp.CppManagedValueTransfer.convertRoot;

/** Compare authored scalar transfer assertions with a collecting native runtime. */
class M14CppNullableTransferTest {
	/**
		Int and Bool recover native defaults only at concrete scalar destinations.
		The runtime fixture below checks Int transfers; the generic-field fixture
		independently checks Bool recovery and preservation of the nullable source.
	 */
	static function admission():Void {
		for (name in ["Int", "Bool"]) {
			final scalar = TyType.fromHintText(name);
			final nullable = TyType.nullable(scalar);
			if (accepts(scalar, nullable) || !supports(scalar, nullable))
				throw name + " conversion admission differs";
			if (!accepts(nullable, nullable) || convertRoot(nullable, nullable, "root", "").length != 0)
				throw name + " nullable copy changed absence";
			final other = TyType.fromHintText(name == "Int" ? "Bool" : "Int");
			for (source in [
				TyType.fromHintText("Dynamic"),
				TyType.fromHintText("String"),
				TyType.fromHintText("Float"),
				other,
				TyType.nullable(other)
			])
				if (supports(scalar, source))
					throw name + " conversion admitted an unrelated source";
		}
	}

	static function main():Void {
		admission();
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_nullable_transfer_seed", mainModule: "Main", requiredModules: ["Array"]});
		final modules = TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index);
		final output = ".tmp/cpp-nullable-transfer";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(modules, false),
			new backend.BackendContext(output, null, "Main", true, fixture.defines));
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
