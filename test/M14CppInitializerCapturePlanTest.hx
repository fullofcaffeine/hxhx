import backend.cpp.CppManagedInitializerStorage;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedFunctionBody;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedInitializerLocals;
import backend.cpp.CppManagedParameterEmitter;
import backend.cpp.CppManagedRuntime;

/** Check that field capture facts retain one shared cell across sibling closures. */
class M14CppInitializerCapturePlanTest {
	static function main():Void {
		final source = "class Main { public var callbacks:Array<Int->Int> = { var x = 7; [function(delta:Int) { x += delta; return x; }, function(ignored:Int) return x]; }; public function new() {} static function main() {} }";
		function projectClass():TypedBackendClassProjection {
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			return typed.getBackendProjection().getClasses()[0];
		}
		final projectedClass = projectClass();
		final owner = projectedClass.getFieldInitializers()[0];
		final catalog = owner.requireCaptureCatalog();
		final plan = new CppManagedInitializerStorage(owner);
		final expressions = catalog.getExpressions();
		if (expressions.length != 2 || plan.getCells().length != 1)
			throw "initializer capture inventory differs";
		final cell = plan.getCells()[0];
		for (expression in expressions)
			if (plan.requireClosure(expression).getCells()[0] != cell)
				throw "sibling closures do not share their exact cell plan";
		final foreignOwner = projectClass().getFieldInitializers()[0];
		final foreign = foreignOwner.requireCaptureCatalog();
		var rejected = false;
		try {
			plan.requireClosure(foreign.getExpressions()[0]);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "foreign closure accepted";
		final locals = new CppManagedInitializerLocals(owner, "initializer_local_");
		final binding = cell.source.binding;
		expectRejection(() -> owner.assertUninitializedLocal(binding), "explicit initializer local initialization cannot be omitted");
		final environments = [
			for (index in 0...expressions.length)
				new CppManagedEnvironmentEmitter(plan, expressions[index], "hxhx_env_initializer_" + index)
		];
		rejected = false;
		try {
			new CppManagedEnvironmentEmitter(plan, foreign.getExpressions()[0], "hxhx_env_foreign");
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "foreign closure environment accepted";
		rejected = false;
		try {
			new CppManagedParameterEmitter(plan, Root(projectedClass.getFunctions()[0]), [], "hxhx_parameters_wrong_root_");
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "initializer capture storage borrowed a method root";
		final initializer = findInitializer(owner, binding);
		final declarations = locals.declare(binding, initializer, "heap", "    ", (value, destination, indent) -> {
			if (!value.match(EInt(7)))
				throw "capture fixture initializer changed";
			return [indent + destination + ".set(hxhx::managed::Value::integer(7));"];
		});
		final output = ".tmp/initializer-capture-cell";
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		// Bodies come from authored Haxe; native invocation and lifetime observation are test scaffolding.
		final entries = new Array<String>();
		for (index in 0...expressions.length) {
			final selected = backend.cpp.CppManagedFunctionOwner.Closure(expressions[index]);
			final access = new CppManagedLocalAccess({
				initializer: owner,
				plan: plan,
				owner: selected,
				parameters: ["hxhx_arg0"],
				temporaryPrefix: "hxhx_parameters_initializer_" + index + "_",
				environmentName: environments[index].nativeName,
				environmentSymbol: "hxhx_environment"
			});
			expectRejection(() -> access.requireExpression(expressions[1 - index]), "managed call is not an exact expression");
			expectRejection(() -> {
				new CppManagedLocalAccess({
					initializer: foreignOwner,
					plan: plan,
					owner: selected,
					parameters: ["argument"],
					temporaryPrefix: "hxhx_parameters_foreign_",
					environmentName: environments[index].nativeName,
					environmentSymbol: "reference"
				});
			}, "closure is not an exact occurrence");
			final rooted = new CppManagedRootedExpression({
				owner: CallableBody(access),
				heap: "hxhx_heap",
				temporaryPrefix: "hxhx_value_initializer_" + index + "_",
				resolve: _ -> {
					throw "fixture has no nested closure";
				}
			});
			entries.push('static '
				+ backend.cpp.CppManagedEntrySignature.render(plan.requireFunction(selected).abi, 'entry' + index)
				+ ' {\n'
				+ access.parameters.render("hxhx_heap")
				+ '\n  hxhx_heap.collect();\n'
				+ new CppManagedFunctionBody(plan, selected).render("hxhx_result", null, backend.cpp.CppManagedBodyServices.fromExpression(rooted))
				+ '\n}\n');
		}
		final constructions = [
			for (index in 0...environments.length)
				environments[index].renderConstruction({
					heap: "heap",
					destination: "callback" + index,
					entry: "entry" + index,
					captures: [{binding: binding, reference: locals.cellReference(binding)}],
					temporaryPrefix: "hxhx_construct_initializer_" + index + "_"
				})
		];
		final code = '#include "ManagedCallable.hpp"\n#include <stdexcept>\n'
			+ [for (environment in environments) environment.render()].join("\n")
				+ "\n"
				+ entries.join("\n")
				+ '\nint main() {\n  hxhx::managed::Heap heap(0);\n  {\n'
				+ '  using Callback = void(hxhx::managed::Root<hxhx::managed::Value>&, hxhx::managed::Value);\n'
				+ '  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CallablePayload<Callback>>> callback0(heap), callback1(heap);\n  {\n'
				+ declarations.join("\n")
				+ '\n    heap.collect();\n    if ('
				+ locals.value(binding)
				+ '.asInteger() != 7) throw std::runtime_error("captured initializer value lost");\n    auto first = '
				+ locals.cellReference(binding)
				+ ';\n    auto second = '
				+ locals.cellReference(binding)
				+
				';\n    first->write(hxhx::managed::Value::integer(8));\n    heap.collect();\n    if (second->read().asInteger() != 8) throw std::runtime_error("cell aliases diverged");\n'
				+ constructions.join("\n")
				+ '\n  }\n  heap.collect();\n'
				+ '  hxhx::managed::Root<hxhx::managed::Value> result(heap);\n'
				+ '  hxhx::managed::ActiveCall<Callback>(heap, callback0.get()).invoke(result, hxhx::managed::Value::integer(3));\n'
				+ '  if (result.get().asInteger() != 11) throw std::runtime_error("environment lost shared cell or argument");\n'
				+ '  heap.collect();\n'
				+ '  hxhx::managed::ActiveCall<Callback>(heap, callback1.get()).invoke(result, hxhx::managed::Value::integer(99));\n'
				+ '  if (result.get().asInteger() != 11) throw std::runtime_error("sibling closure lost shared state");\n'
				+ '  }\n  heap.collect();\n  if (heap.rootCount() != 0 || heap.liveCount() != 0) throw std::runtime_error("initializer cell leaked");\n}\n';
		sys.io.File.saveContent(output + "/Observer.cpp", code);
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				optimization,
				"-fsanitize=address,undefined",
				"-I",
				output,
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0 || Sys.command(timeout, ["30", executable]) != 0)
				throw "initializer captured cell failed native observation";
		}
		Sys.println("INITIALIZER_CAPTURE_PLAN:PASS");
	}

	/** Ownership checks must reject for the intended contract, not an unrelated setup failure. */
	static function expectRejection(action:Void->Void, message:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "initializer capture accepted invalid ownership";
	}

	/** Use the exact authored declaration operand, not a reconstructed storage event. */
	static function findInitializer(owner:TypedBackendFieldInitializerProjection, binding:TyLocalBinding):HxExpr {
		var found:Null<HxExpr> = null;
		final name = owner.getLocalCatalog().projectedName(binding);
		TypedBackendSourceWalk.expression(owner.getExpression(), expression -> {
			switch expression {
				case EVariableDeclaration(selected, _, value, _, _, _) if (selected == name): found = value;
				case _:
			}
		});
		if (found == null)
			throw "initializer binding lost its declaration";
		return found;
	}
}
