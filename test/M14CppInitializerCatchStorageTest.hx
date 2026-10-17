import backend.cpp.CppManagedInitializerLocals;
import backend.cpp.CppManagedInitializerStorage;
import backend.cpp.CppManagedExpressionLocals;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedFunctionBody;
import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedRootedExpression.CppManagedExpressionOwner;

/** Field catch storage must resolve through the field's own exact capture catalog. */
class M14CppInitializerCatchStorageTest {
	static function project():TypedBackendClassProjection {
		final path = "test/oracle/cpp_initializer_catch_storage_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection().getClasses()[0];
	}

	static function reject(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(expected) >= 0)
				return;
			throw failure;
		}
		throw "initializer catch accepted invalid ownership: " + expected;
	}

	static function main():Void {
		final owner = project();
		for (nested in [false, true]) {
			final lines = [
				'#include "ManagedCallable.hpp"',
				'#include "ManagedThrow.hpp"',
				'static void observeCatchEntry(hxhx::managed::Heap&);'
			];
			for (captured in [true, false]) {
				final name = nested ? (captured ? "nested" : "nestedPlain") : (captured ? "captured" : "plain");
				final field = owner.getFieldInitializers().filter(value -> value.getField().getName() == name)[0];
				append(field, nested, captured, lines);
			}
			final directory = ".tmp/cpp-initializer-catch-storage/" + (nested ? "closure" : "field");
			new backend.cpp.CppManagedRuntime().publish(directory);
			sys.io.File.saveContent(directory + "/Generated.hpp", lines.join("\n") + "\n");
			M14CppCatchStorageTest.observe(directory);
			Sys.println("CPP_INITIALIZER_CATCH_STORAGE:" + (nested ? "closure" : "field") + ":PASS");
		}
	}

	/** Reuse real field projections and closure emitters; only handler selection is supplied by the native observer. */
	static function append(field:TypedBackendFieldInitializerProjection, nested:Bool, captured:Bool, lines:Array<String>):Void {
		final plan = new CppManagedInitializerStorage(field);
		final catalog = field.requireCaptureCatalog();
		final closures = catalog.getExpressions();
		if (closures.length != (nested ? 1 : 0) + (captured ? 1 : 0))
			throw "initializer catch fixture lost its authored closures";
		final bindings = catalog.getPlan().getBindings().filter(entry -> entry.creation == CatchEntry);
		if (bindings.length != 1)
			throw "initializer catch fixture lost its exact binding";
		final binding = bindings[0].binding;
		final prefix = "hxhx_initializer_catch_" + (captured ? "capture_" : "plain_");
		final fieldLocals = new CppManagedInitializerLocals(field, prefix);
		var parent:Null<CppManagedLocalAccess> = null;
		final localOwner:CppManagedExpressionOwner = if (nested) {
			parent = new CppManagedLocalAccess({
				initializer: field,
				plan: plan,
				owner: Closure(closures[0]),
				parameters: [],
				temporaryPrefix: "hxhx_parameters_initializer_parent_",
				environmentName: "hxhx_env_initializer_parent",
				environmentSymbol: "parent_environment"
			});
			final declared = plan.getDeclarations(Closure(closures[0])).filter(entry -> entry.creation == CatchEntry);
			if (declared.length != 1 || declared[0].binding != binding)
				throw "initializer closure lost its lexical catch event";
			reject(() -> fieldLocals.renderCatch(binding, "selected", "heap", ""), "exact root declaration event");
			CallableBody(parent);
		} else {
			fieldLocals.binding(field.getLocalCatalog().projectedName(binding));
			reject(() -> fieldLocals.declare(binding, ENull, "heap", "", (_, _, _) -> []), "exact creation event");
			FieldInitializer(field);
		};
		final locals = new CppManagedExpressionLocals(localOwner, prefix);
		reject(() -> locals.renderCatch(binding, "selected.get()", "heap", ""), "rooted value");
		final foreign = project().getFieldInitializers().filter(value -> value.getField().getName() == field.getField().getName())[0];
		final foreignBinding = foreign.requireCaptureCatalog()
			.getPlan()
			.getBindings()
			.filter(entry -> entry.creation == CatchEntry)[0].binding;
		reject(() -> locals.renderCatch(foreignBinding, "selected", "heap", ""), nested ? "exact creation event" : "exact root declaration event");
		if (captured) {
			final closure = closures[nested ? 1 : 0];
			final environment = new CppManagedEnvironmentEmitter(plan, closure, "hxhx_env_initializer_catch_child");
			if (plan.requireClosure(closure).getCells().length != 1
				|| plan.requireClosure(closure).getCells()[0].source.binding != binding)
				throw "initializer child lost its original catch cell";
			lines.push(environment.render());
			final child = new CppManagedLocalAccess({
				initializer: field,
				plan: plan,
				owner: Closure(closure),
				parameters: ["hxhx_arg0"],
				temporaryPrefix: "hxhx_parameters_initializer_child_",
				environmentName: environment.nativeName,
				environmentSymbol: "hxhx_environment"
			});
			reject(() -> child.locals.renderCatch(binding, "selected", "heap", ""), "not a declaration");
			final rooted = new CppManagedRootedExpression({
				owner: CallableBody(child),
				heap: "hxhx_heap",
				temporaryPrefix: "hxhx_value_initializer_child_",
				resolve: _ -> throw "initializer child has no descendant closure"
			});
			lines.push("inline " + backend.cpp.CppManagedEntrySignature.render(plan.requireClosure(closure).abi, "generatedInitializerCatchChild") + " {");
			lines.push(child.parameters.render("hxhx_heap"));
			lines.push(new CppManagedFunctionBody(plan,
				Closure(closure)).render("hxhx_result", null, backend.cpp.CppManagedBodyServices.fromExpression(rooted)));
			lines.push("}");
		}
		lines.push("inline void generatedCatch"
			+ (captured ? "capture" : "plain")
			+ "(hxhx::managed::Heap& heap, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Root<hxhx::managed::Value>& selected) {");
		for (line in locals.renderCatch(binding, "selected", "heap", "  "))
			lines.push(line);
		lines.push("  observeCatchEntry(heap);");
		if (captured) {
			final closure = closures[nested ? 1 : 0];
			final environment = new CppManagedEnvironmentEmitter(plan, closure, "hxhx_env_initializer_catch_child");
			lines.push("  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CallablePayload<"
				+ plan.requireClosure(closure).abi.nativeSignature()
				+ ">>> callback(heap);");
			lines.push(environment.renderConstruction({
				heap: "heap",
				destination: "callback",
				entry: "generatedInitializerCatchChild",
				captures: [{binding: binding, reference: locals.cellReference(binding)}],
				temporaryPrefix: "hxhx_construct_initializer_catch_"
			}));
			lines.push("  output.set(hxhx::managed::Value::managed(callback.get()));");
		} else {
			if (plan.getCells().length != 0)
				throw "uncaptured initializer catch allocated a cell";
			lines.push("  output.set("
				+ (nested ? parent.locals.value(binding) : new CppManagedInitializerLocals(field, prefix + "local_").value(binding))
				+ ");");
		}
		lines.push("}");
		field.assertCurrent();
		var children:Null<Array<HxExpr>> = null;
		TypedBackendSourceWalk.expression(field.getExpression(), value -> {
			if (children == null)
				switch value {
					case ELoweredControl(_, _, entries, _) if (entries.length > 0): children = entries;
					case _:
				}
		});
		if (children == null)
			throw "initializer catch lacks a mutable projected region for its ownership negative";
		final saved = children[0];
		children[0] = EInt(99);
		reject(() -> locals.renderCatch(binding, "selected", "heap", ""),
			nested ? "capture catalog projection was mutated" : "initializer projection was mutated");
		children[0] = saved;
		field.assertCurrent();
	}
}
