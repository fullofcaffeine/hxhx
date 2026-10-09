package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/**
	Keep class-valued runtime operations distinct from Boolean instance tests.
	Class handles reuse the one program-owned descriptor table. Unsupported tests
	still reject before publication; a descriptor alone cannot authorize execution.
 */
function valueType(occurrence:TypedBackendRuntimeTypeOccurrence, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors,
		?context:CppManagedEnclosingApplication):TyType {
	if (occurrence.getValue() == null) {
		if (classes == null)
			throw "managed runtime class value requires its program descriptor plan";
		classes.requireRuntimeDescriptor(occurrence, context);
		return occurrence.getTarget().getValueType();
	}
	if (CppManagedMapTypeTest.selectsTarget(occurrence) || classes == null || classes.instanceTestDescriptor(occurrence, context) == null)
		CppManagedMapTypeTest.matchesFamily(occurrence, classes, enums, context);
	return TyType.fromHintText("Bool");
}

/** Visit every selected occurrence before target output can be published. */
function validate(catalog:TypedBackendRuntimeTypeCatalog, classes:CppManagedClassStorage, enums:CppManagedEnumDescriptors,
		?context:CppManagedEnclosingApplication):Void {
	for (occurrence in catalog.getEntries())
		valueType(occurrence, classes, enums, context);
}

/** Descriptors have static lifetime and occupy the existing common-value alternative. */
function render(input:{
	occurrence:TypedBackendRuntimeTypeOccurrence,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	?context:CppManagedEnclosingApplication,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	valueType(input.occurrence, input.classes, input.enums, input.context);
	if (input.occurrence.getValue() == null) {
		final symbol = input.classes.requireRuntimeDescriptor(input.occurrence, input.context);
		return [
			indent + input.destination + ".set(hxhx::managed::Value::descriptor(&" + symbol + "));"
		];
	}
	final symbol = input.classes == null
		|| CppManagedMapTypeTest.selectsTarget(input.occurrence) ? null : input.classes.instanceTestDescriptor(input.occurrence, input.context);
	if (symbol == null)
		return CppManagedMapTypeTest.render(input, indent);
	final operand = input.destination + "_type_operand";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + operand + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.occurrence.getValue(), operand, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  "
		+ input.destination
		+ ".set(hxhx::managed::Value::boolean(hxhx_runtime_is_of_type("
		+ operand
		+ ".get(), hxhx::managed::Value::descriptor(&"
		+ symbol
		+ "))));");
	lines.push(indent + "}");
	return lines;
}
