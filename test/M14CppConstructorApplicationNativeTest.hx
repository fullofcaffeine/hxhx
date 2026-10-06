import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedFunctionEmitter;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedProgramPlan;

/** Execute the original generic abstract body with its exact applied native storage. */
class M14CppConstructorApplicationNativeTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/abstract_constructor_result_seed/src",
			mainModule: "Main",
			requiredModules: ["Array"]
		});
		// Real library bodies contain source permissions and operator syntax. Consume
		// them through the production shared lowering before backend projection.
		final program = new CppTypedProgramProjection(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index),
			false));
		final classes = new CppManagedClassStorage(program);
		final main = program.requireClass(program.requireClassIdentity("Main")).getFunctions()[0];
		final entries = main.getConstructorCatalog().getEntries();
		if (entries.length != 6)
			throw "original constructor fixture lost a case";
		final application = classes.constructorApplication(entries[5]);
		if (application.receiverType.getTypeArguments()[0].getSemanticKey() != "primitive:String")
			throw "native observer requires the original String application";
		final generated = new CppManagedFunctionEmitter({
			projection: application.projection,
			application: application,
			classes: classes,
			rootSymbol: "generated_constructor",
			symbolPrefix: "hxhx_function_constructor_application"
		}).render();
		final output = ".tmp/cpp-constructor-application";
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + generated);
		sys.io.File.saveContent(output + "/Applications.cpp", new CppManagedProgramPlan(M14CppConstructorApplicationTest.program(), "Main").render());
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		for (optimization in ["-O0", "-O2"]) {
			final binary = output + "/test" + optimization;
			final compileCode = Sys.command(timeout, [
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
				"test/cpp_managed_heap/ConstructorApplicationObserver.cpp",
				"-o",
				binary
			]);
			if (compileCode != 0)
				throw "applied constructor observer did not compile (exit " + compileCode + ", " + optimization + ")";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = try process.exitCode() catch (failure:haxe.Exception) {
				process.close();
				throw "applied constructor observer terminated abnormally: " + stdout + stderr + failure.message;
			};
			process.close();
			if (code != 0 || stderr.length != 0 || stdout != "word\n")
				throw "applied constructor execution differs: " + stdout + stderr;
		}
		Sys.println("CPP_CONSTRUCTOR_APPLICATION_NATIVE:PASS");
	}
}
