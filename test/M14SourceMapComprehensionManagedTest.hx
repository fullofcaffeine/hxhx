import backend.cpp.CppManagedFunctionEmitter;
import backend.cpp.CppManagedRuntime;

/** Execute an authored collection function with real provider types and a native heap observer. */
class M14SourceMapComprehensionManagedTest {
	static function main():Void {
		runFixture({
			sourceRoot: "test/oracle/source_comprehension_seed/map_execution",
			module: "MapExecution",
			observer: "test/cpp_managed_heap/MapComprehensionObserver.cpp",
			output: ".tmp/source-map-comprehension-managed",
			marker: "SOURCE_MAP_COMPREHENSION_NATIVE:PASS"
		});
		Sys.println("SOURCE_MAP_COMPREHENSION_MANAGED:PASS");
	}

	/** Keep the full map contract and focused storage observer on identical native checks. */
	public static function runFixture(input:{
		sourceRoot:String,
		module:String,
		observer:String,
		output:String,
		marker:String
	}):Void {
		// Resolve the real provider closure before selecting this observer's authored methods.
		final fixture = CppResolvedFixture.load({
			sourceRoot: input.sourceRoot,
			mainModule: input.module,
			requiredModules: []
		});
		final functions = fixture.main.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final declarations = [
			for (fn in functions) {
				final projection = TypedBodySource.functionProjection(fn);
				final name = HxFunctionDecl.getName(projection.getDeclaration());
				new CppManagedFunctionEmitter({projection: projection, rootSymbol: "generated_" + name, symbolPrefix: "hxhx_function_" + name}).render();
			}
		];
		final output = input.output;
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + declarations.join("\n"));
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "managed comprehension changed authored typed source";
		sys.io.File.copy(input.observer, output + "/Observer.cpp");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
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
				throw "managed comprehension failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stderr.length != 0 || stdout != input.marker + "\n")
				throw "managed comprehension observation failed: " + stdout + stderr;
		}
	}
}
