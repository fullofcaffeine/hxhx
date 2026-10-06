package backend.cpp;

/** Evaluate map, key, and value in source order, keeping all three roots through allocation. */
function render(input:{
	map:HxExpr,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	?casts:CppManagedCastPlan,
	key:HxExpr,
	value:HxExpr,
	mapType:TyType,
	keyType:TyType,
	valueType:TyType,
	heap:String,
	prefix:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final storage = CppManagedMapStorage.select(input.mapType, input.classes, input.enums);
	if (storage.keyType.getSemanticKey() != input.keyType.getSemanticKey()
		|| !CppManagedValueTransfer.accepts(storage.valueType, input.valueType, input.casts))
		throw "managed map insertion requires its exact key and value types";
	final map = input.prefix + "map";
	final key = input.prefix + "key";
	final value = input.prefix + "value";
	final lines = [indent + "{"];
	for (name in [map, key, value])
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + input.heap + ");");
	for (operand in [
		{expression: input.map, root: map},
		{expression: input.key, root: key},
		{expression: input.value, root: value}
	])
		for (line in input.renderValue(operand.expression, operand.root, indent + "  "))
			lines.push(line);
	lines.push(indent
		+ "  "
		+ map
		+ ".get().asManaged().as<hxhx::managed::"
		+ storage.payload
		+ ">()->insert("
		+ CppManagedMapStorage.renderKey(input.mapType, key + ".get()", input.classes, input.enums)
		+ ", "
		+ value
		+ ".get());");
	lines.push(indent + "}");
	return lines;
}
