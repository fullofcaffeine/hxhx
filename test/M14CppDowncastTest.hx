/** Compare class narrowing with native source assertions and collecting sanitizer builds. */
class M14CppDowncastTest {
	static function main():Void {
		checkBounds();
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_downcast_seed", mainModule: "Main", requiredModules: ["Std"]});
		final source = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final program = new backend.cpp.CppTypedProgramProjection(source);
		final plan = new backend.cpp.CppManagedProgramPlan(program, "Main");
		final boundary = M14CppDowncastBoundary.header(program, plan);
		final output = ".tmp/cpp-downcast";
		final result = backend.cpp.CppTargetCore.emit(source, new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "native downcast assertions failed";
		sys.io.File.saveContent(output + "/DowncastBoundary.hpp", boundary);
		CppManagedAssertionFixture.sanitizers(output, "CPP_DOWNCAST", "test/cpp_managed_heap/DowncastObserver.cpp");
		Sys.println("CPP_DOWNCAST:PASS");
	}

	/** Both compilers must reject a target class that violates the source type bound. */
	static function checkBounds():Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", "test/oracle/cpp_downcast_seed", "-main", "Invalid", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code == 0 || stdout.length != 0 || stderr.indexOf("Constraint check failure for downcast.S") < 0)
			throw "upstream accepted an invalid downcast bound: " + stderr;
		var rejected = false;
		try
			CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_downcast_seed", mainModule: "Invalid", requiredModules: ["Std"]})
		catch (error:haxe.Exception) {
			if (error.message.indexOf("Constraint check failure for downcast.S") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "local typing accepted an invalid downcast bound";
		Sys.println("CPP_DOWNCAST_BOUNDS:PASS");
	}
}
