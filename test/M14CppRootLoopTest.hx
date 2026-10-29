import backend.cpp.CppManagedFunctionEmitter;
import backend.cpp.CppManagedRuntime;

/** Real provider typing and an independent native observer exercise ordinary method loops. */
class M14CppRootLoopTest {
	static function rejects(action:Void->Void):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf("absent from this exact function projection") >= 0)
				return;
			throw failure;
		}
		throw "foreign or copied statement acquired loop control authority";
	}

	static function main():Void {
		M14StatementControlProjectionTest.main();
		final root = "test/oracle/cpp_root_loop_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "RootLoops", requiredModules: ["Array"]});
		final functions = fixture.main.getTypedClasses()[0].getFunctions();
		final declarations = [];
		for (fn in functions) {
			final projection = TypedBodySource.functionProjection(fn);
			final foreign = TypedBodySource.functionProjection(fn);
			for (statement in projection.getBody()) {
				TypedBackendSourceWalk.statement(statement, _ -> {}, entry -> {
					switch entry {
						case SForIn(name, iterable, body, position):
							projection.requireStatementControl(entry);
							rejects(() -> foreign.requireStatementControl(entry));
							rejects(() -> projection.requireStatementControl(SForIn(name, iterable, body, position)));
						case _:
					}
				});
			}
			final name = HxFunctionDecl.getName(projection.getDeclaration());
			declarations.push(new CppManagedFunctionEmitter({
				projection: projection,
				rootSymbol: "generated_" + name,
				symbolPrefix: "hxhx_function_" + name
			}).render());
		}
		final output = ".tmp/cpp-root-loops";
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + declarations.join("\n"));
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
				"test/cpp_managed_heap/RootLoopObserver.cpp",
				"-o",
				binary
			]) != 0)
				throw "ordinary method loop observer failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stderr.length != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
				throw "ordinary method loop behavior differs: " + stdout + stderr;
		}
		Sys.println("CPP_ROOT_LOOPS:PASS");
	}
}
