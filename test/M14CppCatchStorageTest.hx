import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedFunctionBody;
import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedRuntime;

/** Observe catch-entry storage in generated closure code; native handler selection remains a separate contract. */
class M14CppCatchStorageTest {
	static function reject(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "catch storage accepted invalid ownership: " + expected;
	}

	static function main():Void {
		final path = "test/oracle/cpp_catch_storage_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final functions = TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final lines = [
			'#include "ManagedCallable.hpp"',
			'#include "ManagedThrow.hpp"',
			'static void observeCatchEntry(hxhx::managed::Heap&);'
		];
		for (fn in functions) {
			final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
			if (name != "capture" && name != "plain")
				continue;
			final projection = TypedBodySource.functionProjection(fn);
			final plan = new CppManagedStoragePlan(projection);
			final access = new CppManagedLocalAccess({
				projection: projection,
				plan: plan,
				owner: Root(projection),
				parameters: ["seed"],
				temporaryPrefix: "hxhx_parameters_catch_" + name + "_"
			});
			final catches = plan.getDeclarations(Root(projection)).filter(entry -> entry.creation == CatchEntry);
			if (catches.length != 1)
				throw "storage fixture lost its single exact catch event";
			final binding = catches[0].binding;
			for (entry in plan.getDeclarations(Root(projection)))
				if (entry.creation == Declaration)
					reject(() -> access.locals.renderCatch(entry.binding, "selected", "heap", ""), "exact creation event");
			reject(() -> access.locals.renderDeclaration(binding, ENull, "heap", "", (_, _, _) -> []), "declaration event");
			reject(() -> access.locals.renderIteration(binding, "selected", "heap", ""), "exact creation event");
			reject(() -> access.locals.renderCatch(binding, "selected.get()", "heap", ""), "exact creation event");
			// Rebuilding the same source gives equal semantic keys but distinct binding
			// objects. A different projection cannot authorize this allocation event.
			final otherModule = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
			final otherFn = TyperStage.typeResolvedModule(otherModule, TyperIndex.build([otherModule]))
				.getTypedClasses()[0].getFunctions().filter(value -> HxFunctionDecl.getName(value.getSourceDeclaration()) == name)[0];
			final other = TypedBodySource.functionProjection(otherFn);
			final otherBinding = new CppManagedStoragePlan(other).getDeclarations(Root(other)).filter(entry -> entry.creation == CatchEntry)[0].binding;
			reject(() -> access.locals.renderCatch(otherBinding, "selected", "heap", ""), "exact creation event");
			final closures = projection.requireCaptureCatalog().getExpressions();
			if (name == "capture") {
				if (closures.length != 1 || plan.getCells().length != 1)
					throw "captured handler must own exactly one mutable cell";
				final closure = closures[0];
				final environmentName = "hxhx_env_catch_storage";
				lines.push(new CppManagedEnvironmentEmitter(plan, closure, environmentName).render());
				final child = new CppManagedLocalAccess({
					projection: projection,
					plan: plan,
					owner: Closure(closure),
					parameters: ["hxhx_arg0"],
					temporaryPrefix: "hxhx_parameters_catch_child_",
					environmentName: environmentName,
					environmentSymbol: "hxhx_environment"
				});
				reject(() -> child.locals.renderCatch(binding, "selected", "heap", ""), "not a declaration");
				final childRooted = new CppManagedRootedExpression({
					owner: CallableBody(child),
					heap: "hxhx_heap",
					temporaryPrefix: "hxhx_value_catch_child_",
					resolve: _ -> throw "catch child has no nested closure"
				});
				lines.push("inline " + backend.cpp.CppManagedEntrySignature.render(plan.requireClosure(closure).abi, "generatedCatchChild") + " {");
				lines.push(child.parameters.render("hxhx_heap"));
				lines.push(new CppManagedFunctionBody(plan,
					Closure(closure)).render("hxhx_result", null, backend.cpp.CppManagedBodyServices.fromExpression(childRooted)));
				lines.push("}");
			}
			lines.push("inline void generatedCatch"
				+ name
				+ "(hxhx::managed::Heap& heap, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Root<hxhx::managed::Value>& selected) {");
			for (line in access.locals.renderCatch(binding, "selected", "heap", "  "))
				lines.push(line);
			lines.push("  observeCatchEntry(heap);");
			if (name == "capture") {
				final rooted = new CppManagedRootedExpression({
					owner: CallableBody(access),
					heap: "heap",
					temporaryPrefix: "hxhx_value_catch_root_",
					resolve: expression -> {
						if (expression != closures[0])
							throw "foreign closure";
						return {expression: expression, environmentName: "hxhx_env_catch_storage", entrySymbol: "generatedCatchChild"};
					}
				});
				for (line in rooted.render(closures[0], "output", "  "))
					lines.push(line);
			} else {
				if (closures.length != 0 || plan.getCells().length != 0)
					throw "uncaptured handler allocated a capture cell";
				lines.push("  output.set(" + access.locals.value(binding) + ");");
			}
			lines.push("}");
			plan.assertCurrent();
			final body = projection.getBody();
			body.push(SExpr(EInt(99), HxPos.unknown()));
			reject(() -> access.locals.renderCatch(binding, "selected", "heap", ""), "projection was mutated");
			body.pop();
			plan.assertCurrent();
		}
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "catch storage emission changed typed source";
		final directory = ".tmp/cpp-catch-storage";
		new CppManagedRuntime().publish(directory);
		sys.io.File.saveContent(directory + "/Generated.hpp", lines.join("\n") + "\n");
		observe(directory);
	}

	/** Every lexical owner runs the same independent post-unwind lifetime and failure observer. */
	public static function observe(directory:String):Void {
		sys.io.File.copy("test/cpp_managed_heap/CatchStorageObserver.cpp", directory + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final binary = directory + "/test" + optimization;
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
				directory,
				directory + "/Observer.cpp",
				"-o",
				binary
			]) != 0)
				throw "catch storage native observer did not compile";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stderr != "" || stdout != "CPP_CATCH_STORAGE_NATIVE:PASS\n")
				throw "catch storage observation failed: " + stdout + stderr;
			Sys.println("CPP_CATCH_STORAGE:" + optimization + ":PASS");
		}
	}
}
