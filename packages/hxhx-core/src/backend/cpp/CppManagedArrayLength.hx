package backend.cpp;

/** Select the actual standard Array field, never a same-name user field. */
function selects(occurrence:Null<TypedBackendFieldOccurrence>):Bool {
	return occurrence != null
		&& occurrence.getField().getModulePath() == 'Array'
		&& occurrence.getField().getCanonicalKey() == 'Array#instance#length';
}

/** Exact executable ownership is checked by the caller before this provider contract. */
function require(occurrence:TypedBackendFieldOccurrence):Void {
	if (!selects(occurrence))
		throw 'managed Array.length requires its exact standard field';
	final field = occurrence.getField();
	if (field.getIsStatic()
		|| field.getType().getSemanticKey() != 'primitive:Int'
		|| occurrence.getType().getSemanticKey() != 'primitive:Int'
		|| occurrence.getReceiver() != ValueReceiver
		|| field.getPropertyGet() != 'default'
		|| field.getPropertySet() != 'null')
		throw 'managed Array.length requires its exact read-only Int field contract';
}

/**
	Read size from the selected array allocation, rather than allocating an ordinary
	class layout for the Array extern. Evaluate the receiver once and retain its root
	through effects. A checked bound prevents narrowing a native size into a wrong Int.
 */
function read(input:{
	occurrence:TypedBackendFieldOccurrence,
	heap:String,
	destination:String,
	renderReceiver:(TypedBackendFieldOccurrence, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.occurrence);
	final receiver = input.destination + '_length_receiver';
	final size = input.destination + '_length_size';
	final lines = [
		indent + '{',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + receiver + '(' + input.heap + ');'
	];
	for (line in input.renderReceiver(input.occurrence, receiver, indent + '  '))
		lines.push(line);
	lines.push(indent
		+ '  if ('
		+ receiver
		+ '.get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument("array length has no array");');
	lines.push(indent + '  const auto ' + size + ' = ' + receiver + '.get().asManaged().as<hxhx::managed::ArrayPayload>()->size();');
	lines.push(indent
		+ '  if ('
		+ size
		+ ' > static_cast<std::size_t>(2147483647)) throw std::length_error("array length exceeds Haxe Int capacity");');
	lines.push(indent + '  ' + input.destination + '.set(hxhx::managed::Value::integer(static_cast<std::int32_t>(' + size + ')));');
	lines.push(indent + '}');
	return lines;
}
