import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedProgramPlan;

/** Observe the normal generated program runner, including generic abstract conversion and once-only operand evaluation. */
class M14CppManagedAbstractInitializerTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/cpp_managed_abstract_initializer_seed/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final program = new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], false);
		final projection = new CppTypedProgramProjection(program);
		final initializer = projection.getModules()[0].projection.getClasses()[0].getFieldInitializers()[0];
		final conversion = initializer.findCast(initializer.getExpression());
		if (conversion == null
			|| !conversion.isRepresentationPreserving()
			|| conversion.getSourceType().getSemanticKey() != "primitive:Int"
			|| conversion.getTargetType().getNominalIdentity().getCanonicalName() != "Main.Box")
			throw "field initializer lost its exact selected generic conversion";
		var rejected = false;
		try
			conversion.assertCurrent("another-owner", initializer.getBodyRevision())
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf("another executable") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "cast borrowed a foreign executable";
		for (header in ["", "from Bool"]) {
			final invalid = "class Main { static var value:Box<Int> = 7; static function main():Void {} } abstract Box<T>(T) " + header + " {}";
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(invalid, "Main.hx"));
			final invalidProgram = new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false);
			rejected = false;
			try
				new CppManagedProgramPlan(new CppTypedProgramProjection(invalidProgram), "Main").render()
			catch (failure:haxe.Exception) {
				if (failure.message.indexOf("explicit typed conversion") < 0)
					throw failure;
				rejected = true;
			}
			if (!rejected)
				throw "matching backing storage admitted an undeclared field conversion";
		}
		final output = ".tmp/managed-abstract-initializer";
		CppTargetCore.emit(program, new BackendContext(output, output + "/Main.cpp", "Main", true, false, new haxe.ds.StringMap()));
		sys.io.File.copy("test/cpp_managed_heap/AbstractInitializerObserver.cpp", output + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final binary = output + "/test" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				"-Wall",
				"-Wextra",
				"-Werror",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-I",
				output,
				output + "/Observer.cpp",
				"-o",
				binary
			]) != 0)
				throw "startup observer failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0
				|| stderr.length != 0
				|| stdout != sys.io.File.getContent("test/fixtures/cpp_managed_abstract_initializer_seed/expected.stdout"))
				throw "startup observation failed: " + stdout + stderr;
		}
		Sys.println("CPP_MANAGED_ABSTRACT_INITIALIZER:PASS");
	}
}
