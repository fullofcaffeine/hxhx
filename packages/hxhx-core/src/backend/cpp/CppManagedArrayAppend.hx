package backend.cpp;

/** Appending preserves the selected element representation; conversions need their own plan. */
function requireTypes(arrayType:TyType, valueType:TyType, ?casts:CppManagedCastPlan):Void {
	CppManagedClosureAbi.assertComplete(arrayType);
	CppManagedClosureAbi.assertComplete(valueType);
	var selected = arrayType;
	while (selected.getNullableInner() != null)
		selected = selected.getNullableInner();
	final identity = selected.getNominalIdentity();
	final arguments = selected.getTypeArguments();
	if (identity == null
		|| identity.getCanonicalName() != 'Array'
		|| arguments.length != 1
		|| !CppManagedValueTransfer.accepts(arguments[0], valueType, casts))
		throw 'managed array append requires its exact selected element type';
}

/** Evaluate the selected array and yield once, retaining both roots through allocation. */
function render(input:{
	array:HxExpr,
	value:HxExpr,
	arrayType:TyType,
	valueType:TyType,
	?casts:CppManagedCastPlan,
	heap:String,
	prefix:String,
	?destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	requireTypes(input.arrayType, input.valueType, input.casts);
	final array = input.prefix + "array";
	final element = input.prefix + "element";
	final payload = input.prefix + 'payload';
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Value> "
		+ array
		+ "("
		+ input.heap
		+ "), "
		+ element
		+ "("
		+ input.heap
		+ ");"];
	for (line in input.renderValue(input.array, array, indent + "  "))
		lines.push(line);
	for (line in input.renderValue(input.value, element, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ '  if ('
		+ array
		+ '.get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument("array append has no array");');
	lines.push(indent + '  const auto ' + payload + ' = ' + array + '.get().asManaged().as<hxhx::managed::ArrayPayload>();');
	// Check before mutation so the public Int length never narrows an oversized native size.
	lines.push(indent
		+ '  if ('
		+ payload
		+ '->size() >= static_cast<std::size_t>(2147483647)) throw std::length_error("array append exceeds Haxe Int length");');
	lines.push(indent + '  ' + payload + '->append(' + element + '.get());');
	if (input.destination != null)
		lines.push(indent
			+ '  '
			+ input.destination
			+ '.set(hxhx::managed::Value::integer(static_cast<std::int32_t>('
			+ payload
			+ '->size())));');
	lines.push(indent + "}");
	return lines;
}
