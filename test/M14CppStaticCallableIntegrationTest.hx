import backend.BackendContext;
import backend.BackendRegistry;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedStaticCallable.declaration as staticDeclaration;
import backend.cpp.CppManagedStaticCallable.requireTarget;
import backend.cpp.CppManagedStaticStorage;

/** Compile authored static function values and compare the real executable with an upstream-checked contract. */
class M14CppStaticCallableIntegrationTest {
	static function program():MacroExpandedProgram {
		final fixture = "test/fixtures/cpp_static_callable/";
		final resolved = [
			for (name in ["Main", "Sys"]) {
				final path = fixture + name + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(sys.io.File.getContent(path), path));
			}
		];
		final index = TyperIndex.build(resolved);
		final typed = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		return MacroStage.expandProgram(typed, []);
	}

	static function rejects(message:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) >= 0)
				return;
			throw error;
		}
		throw "Expected rejection: " + message;
	}

	/** Matching spelling and semantic keys cannot authorize facts from another compilation. */
	static function ownership(source:MacroExpandedProgram):Void {
		final projected = new CppTypedProgramProjection(source);
		final owner = projected.getModules()[0].projection.getClasses()[0];
		final foreignProgram = new CppTypedProgramProjection(program());
		final foreign = foreignProgram.getModules()[0].projection.getClasses()[0];
		final main = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "main")[0];
		final method = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "twice")[0];
		final other = foreign.getFunctions().filter(fn -> fn.getStableIdentity() == method.getStableIdentity())[0];
		final catalog = main.requireCaptureCatalog();
		final occurrence = catalog.getCallableExpressions().filter(entry -> staticDeclaration(entry.source) == method.requireSemanticDeclaration())[0];
		if (occurrence == null || other == null || catalog.findCallableExpression(EIdent("twice")) != null)
			throw "Static method facts require the exact retained occurrence";
		requireTarget(occurrence.source, _ -> Source(method, "hxhx_method_test"));
		rejects("another typed program", () -> {
			requireTarget(occurrence.source, _ -> Source(other, "hxhx_method_test"));
		});
		final foreignStorage = new CppManagedStaticStorage(foreignProgram, "hxhx_statics_foreign");
		rejects("another typed program", () -> {
			foreignStorage.callableMember(method.requireSemanticDeclaration());
		});
		final published = new CppManagedStaticStorage(projected, "hxhx_statics_published");
		published.render();
		rejects("before layout publication", () -> {
			published.callableMember(method.requireSemanticDeclaration());
		});
	}

	static function main():Void {
		final fixture = "test/fixtures/cpp_static_callable/";
		final source = program();
		ownership(source);
		final context = new BackendContext(".tmp/cpp-static-callable", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(source, context);
		if (!result.builtExecutable)
			throw "Expected a native executable for static function values";
		final expected = sys.io.File.getContent(fixture + "expected.stdout");
		execute(result.entryPath, expected);
		final stress = ".tmp/cpp-static-callable/stress";
		if (Sys.command("c++", [
			"-std=c++17",
			"-Wall",
			"-Wextra",
			"-Werror",
			"-I.tmp/cpp-static-callable/src",
			fixture + "Stress.cpp",
			"-o",
			stress
		]) != 0)
			throw "Static callable collection observer did not compile";
		execute(stress, expected + expected);
		Sys.println("CPP_STATIC_CALLABLE:PASS");
	}

	/** Both ordinary execution and collecting heaps must preserve the same authored observations. */
	static function execute(path:String, expected:String):Void {
		final process = new sys.io.Process(path, []);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "Static function value execution differs from its contract: " + output + errors;
	}
}
