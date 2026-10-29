import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedStaticStorage;
import backend.cpp.CppTypedProgramProjection;

/** Initializers use their own typed catalogs and commit values through generated code. */
class M14CppManagedInitializerTest {
	static function rejects(run:Void->Void, message:String):Void {
		try {
			run();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "initializer accepted foreign or mutated facts";
	}

	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/cpp_managed_initializer_seed/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final storage = new CppManagedStaticStorage(program, "hxhx_statics_initializer_fixture");
		final emitter = new CppManagedProgramEmitter({
			functions: [
				for (fn in owner.getFunctions())
					{
						projection: fn,
						rootSymbol: "generated_" + HxFunctionDecl.getName(fn.getDeclaration()),
						symbolPrefix: "hxhx_function_initializer_" + HxFunctionDecl.getName(fn.getDeclaration())
					}
			],
			output: [],
			statics: storage
		});
		final declarations = [emitter.render()];
		final initializers = owner.getFieldInitializers();
		for (initializer in initializers) {
			final symbol = "hxhx_initializer_" + initializer.getField().getName();
			final emitted = emitter.renderInitializer(initializer, symbol);
			if (emitted != emitter.renderInitializer(initializer, symbol))
				throw "initializer emission is not deterministic";
			declarations.push(emitted);
		}
		final another = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getBackendProjection().getClasses()[0].getFieldInitializers()[0];
		rejects(() -> {
			emitter.renderInitializer(another, "hxhx_initializer_foreign");
		}, "another program");
		final aggregate = initializers[2];
		rejects(() -> {
			aggregate.requireAggregate(EAnon(["value", "label"], [EInt(8), EString("startup")]));
		}, "absent from the current initializer");
		switch aggregate.getExpression() {
			case EAnon(_, values):
				final saved = values[0];
				values[0] = EInt(99);
				rejects(aggregate.assertCurrent, "initializer projection was mutated");
				values[0] = saved;
				aggregate.assertCurrent();
			case _:
				throw "fixture lost its authored record initializer";
		}
		final output = ".tmp/managed-initializer";
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output
			+ "/Generated.hpp",
			'#include "ManagedCallable.hpp"\n'
			+ declarations.join("\n")
			+ "\nvoid publishStorage(hxhx::managed::Heap& heap) { hxhx::managed::Root<hxhx::managed::Ref<"
			+ storage.nativeName
			+ ">> destination(heap); "
			+ storage.renderAllocation("heap", "destination")
			+ " }\n");
		sys.io.File.copy("test/cpp_managed_heap/InitializerObserver.cpp", output + "/Observer.cpp");
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
				throw "managed initializer failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0
				|| stderr.length != 0
				|| stdout != sys.io.File.getContent("test/fixtures/cpp_managed_initializer_seed/expected.stdout"))
				throw "managed initializer observation failed: " + stdout + stderr;
		}
		program.assertCurrent();
		Sys.println("CPP_MANAGED_INITIALIZER:PASS");
	}
}
