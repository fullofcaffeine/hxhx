package backend.cpp;

/**
	Write through the selected Array view without retaining a native element address.
	Pinned Haxe 4.3.7/hxcpp observations evaluate the value, receiver, then index,
	including when the result is discarded. Negative indices leave storage unchanged.
	Growth fills gaps using the view's element default, even for a shared Dynamic
	payload. Roots retain all operands through calls and collection; native storage
	only appends or replaces the values selected by this Haxe-owned policy.
 */
function render(input:{
	receiver:HxExpr,
	index:HxExpr,
	value:HxExpr,
	receiverType:TyType,
	indexType:TyType,
	valueType:TyType,
	?casts:CppManagedCastPlan,
	defaultValue:TyType->String,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final element = CppManagedArrayRead.elementType(input.receiverType, input.indexType);
	if (!CppManagedValueTransfer.supports(element, input.valueType, input.casts))
		throw 'managed array assignment requires an explicit typed conversion';
	if (input.defaultValue == null)
		throw 'managed array assignment requires program-owned element defaults';
	final absent = input.defaultValue(element);
	final array = input.prefix + 'array';
	final index = input.prefix + 'index';
	final value = input.prefix + 'value';
	final payload = input.prefix + 'payload';
	final offset = input.prefix + 'offset';
	final lines = [indent + '{',
		indent
		+ '  hxhx::managed::Root<hxhx::managed::Value> '
		+ array
		+ '('
		+ input.heap
		+ '), '
		+ index
		+ '('
		+ input.heap
		+ '), '
		+ value
		+ '('
		+ input.heap
		+ ');'];
	for (line in input.renderValue(input.value, value, indent + '  '))
		lines.push(line);
	for (line in CppManagedValueTransfer.convertRoot(element, input.valueType, value, indent + '  ', input.casts))
		lines.push(line);
	for (line in input.renderValue(input.receiver, array, indent + '  '))
		lines.push(line);
	for (line in input.renderValue(input.index, index, indent + '  '))
		lines.push(line);
	lines.push(indent
		+ '  if ('
		+ array
		+ '.get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument("array assignment has no array");');
	lines.push(indent + '  const auto ' + payload + ' = ' + array + '.get().asManaged().as<hxhx::managed::ArrayPayload>();');
	lines.push(indent + '  const auto ' + offset + ' = ' + CppManagedInteger.numericValue(input.indexType, index + '.get()') + ';');
	lines.push(indent + '  if (' + offset + ' >= 0) {');
	lines.push(indent
		+ '    while ('
		+ payload
		+ '->size() <= static_cast<std::size_t>('
		+ offset
		+ ')) '
		+ payload
		+ '->append('
		+ absent
		+ ');');
	lines.push(indent + '    ' + payload + '->write(static_cast<std::size_t>(' + offset + '), ' + value + '.get());');
	lines.push(indent + '  }');
	if (input.destination != null)
		lines.push(indent + '  ' + input.destination + '.set(' + value + '.get());');
	lines.push(indent + '}');
	return lines;
}
