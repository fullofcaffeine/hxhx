import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedStaticStorage;
import backend.cpp.CppTypedProgramProjection;

/** Exercise authored field access through generated storage with a separately written native observer. */
class M14CppManagedStaticFieldTest {
	static function rejects(run:Void->Void, message:String):Void {
		try {
			run();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "managed static access accepted invalid ownership or write permission";
	}

	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/cpp_managed_static_field_seed/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final storage = new CppManagedStaticStorage(program, "hxhx_statics_fixture");
		final methods = program.getModules()[0].projection.getClasses()[0].getFunctions();
		final separate = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getBackendProjection().getClasses()[0].getFunctions()[0];
		rejects(() -> storage.assertFunction(separate), "another program");
		final immutableSource = new ResolvedModule("Immutable", "Immutable.hx",
			ParserStage.parse("class Immutable { public static final value:Int = 3; static function read():Int { return value; } }", "Immutable.hx"));
		final immutableProgram = new CppTypedProgramProjection(new MacroExpandedProgram([
			TyperStage.typeResolvedModule(immutableSource, TyperIndex.build([immutableSource]))
		], false));
		final immutableStorage = new CppManagedStaticStorage(immutableProgram, "hxhx_statics_immutable");
		final immutableRead = immutableProgram.getModules()[0].projection.getClasses()[0].getFunctions()[0];
		var checkedImmutable = false;
		for (statement in immutableRead.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final field = immutableRead.findField(expression);
				if (field != null) {
					immutableStorage.member(field);
					rejects(() -> {
						immutableStorage.member(field, true);
					}, "immutable-field binding");
					checkedImmutable = true;
				}
			}, _ -> {});
		if (!checkedImmutable)
			throw "immutable field regression lost its selected read";
		final functions:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (method in methods)
				{
					projection: method,
					rootSymbol: "generated_" + HxFunctionDecl.getName(method.getDeclaration()),
					symbolPrefix: "hxhx_function_static_" + HxFunctionDecl.getName(method.getDeclaration())
				}
		];
		final emitter = new CppManagedProgramEmitter({functions: functions, output: [], statics: storage});
		final generated = emitter.render();
		program.assertCurrent();
		if (generated != emitter.render())
			throw "managed static emission is not deterministic";
		final output = ".tmp/managed-static-fields";
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output
			+ "/Generated.hpp",
			'#include "ManagedCallable.hpp"\n'
			+ generated
			+ "\nvoid publishStorage(hxhx::managed::Heap& heap) { hxhx::managed::Root<hxhx::managed::Ref<"
			+ storage.nativeName
			+ ">> destination(heap); "
			+ storage.renderAllocation("heap", "destination")
			+ " }\n");
		sys.io.File.copy("test/cpp_managed_heap/StaticFieldObserver.cpp", output + "/Observer.cpp");
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
				throw "managed static fields failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0
				|| stderr.length != 0
				|| stdout != sys.io.File.getContent("test/fixtures/cpp_managed_static_field_seed/expected.stdout"))
				throw "managed static native observation failed: " + stdout + stderr;
		}
		Sys.println("CPP_MANAGED_STATIC_FIELDS:PASS");
	}
}
