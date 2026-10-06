package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedConstructor.CppManagedConstructorTarget;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodTarget;

/**
	Render an initializer as its own executable with a temporary result root.
	This emitter preserves field and aggregate catalogs and reuses ordinary value
	sequencing and commits the field only after evaluation succeeds. The enclosing
	startup plan owns invocation order and once-only execution.
	Local declarations and closures require initializer capture planning and remain
	explicitly unsupported here; no synthetic method lends them unrelated facts.
 */
function render(input:{
	projection:TypedBackendFieldInitializerProjection,
	statics:CppManagedStaticStorage,
	symbol:String,
	resolveStatic:String->CppManagedStaticTarget,
	?casts:CppManagedCastPlan,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	?defaultValue:TyType->String,
	?resolveConstructor:String->CppManagedConstructorTarget,
	?resolveInstance:(TypedBackendInstanceCallOccurrence, Null<CppManagedEnclosingApplication>) -> CppManagedInstanceMethodTarget
}):String {
	if (input == null
		|| input.projection == null
		|| input.statics == null
		|| input.symbol == null
		|| !~/^hxhx_initializer_[A-Za-z0-9_]+$/.match(input.symbol))
		throw "managed initializer requires its exact projection and allocated symbol";
	input.statics.assertInitializer(input.projection);
	final target = input.statics.initializerTarget(input.projection);
	CppManagedRuntimeType.validate(input.projection.getRuntimeTypeCatalog(), input.classes, input.enums);
	final expression = input.projection.getExpression();
	final emitter = new CppManagedRootedExpression({
		owner: FieldInitializer(input.projection),
		heap: "hxhx_heap",
		temporaryPrefix: "hxhx_value_" + input.symbol + "_",
		resolve: _ -> {
			throw "managed initializer requires its own closure entry plan";
		},
		resolveStatic: input.resolveStatic,
		statics: input.statics,
		casts: input.casts,
		classes: input.classes,
		enums: input.enums,
		defaultValue: input.defaultValue,
		resolveConstructor: input.resolveConstructor,
		resolveInstance: input.resolveInstance
	});
	if (!emitter.acceptsStoredTransfer(expression, target.type))
		throw "managed field initializer requires an explicit typed conversion";
	final lines = [
		"inline void " + input.symbol + "(hxhx::managed::Heap& hxhx_heap) {",
		"  const auto hxhx_storage = hxhx_heap.requireStatic<" + input.statics.nativeName + ">();",
		"  hxhx::managed::Root<hxhx::managed::Value> hxhx_result(hxhx_heap);"
	];
	for (line in emitter.render(expression, "hxhx_result", "  "))
		lines.push(line);
	lines.push("  hxhx_storage->" + target.member + ".write(hxhx_result.get());");
	lines.push("}");
	input.statics.assertInitializer(input.projection);
	return lines.join("\n");
}
