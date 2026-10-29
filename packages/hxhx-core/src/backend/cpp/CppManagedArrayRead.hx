package backend.cpp;

/** Array identity selects the element type; only Int or nullable Int storage may supply an index. */
function elementType(receiver:TyType, index:TyType):TyType {
	CppManagedClosureAbi.assertComplete(receiver);
	CppManagedClosureAbi.assertComplete(index);
	var array = receiver;
	while (array.getNullableInner() != null)
		array = array.getNullableInner();
	final identity = array.getNominalIdentity();
	if (identity == null
		|| identity.getCanonicalName() != 'Array'
		|| array.getTypeArguments().length != 1
		|| !CppManagedInteger.integerType(index))
		throw 'managed array read requires the resolved Array provider and an Int index';
	return array.getTypeArguments()[0];
}

/**
	Retain the selected array before index effects can replace its source variable.
	Copy the element after those effects; no native element address crosses a call
	or collection. Missing indices use Haxe-selected native defaults. Null receivers
	fail after index evaluation, preserving the observed upstream effect order.
 */
function render(input:{
	receiver:HxExpr,
	index:HxExpr,
	receiverType:TyType,
	indexType:TyType,
	defaultValue:TyType->String,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final type = elementType(input.receiverType, input.indexType);
	if (input.defaultValue == null)
		throw 'managed array read requires its program-owned default selection';
	final absent = input.defaultValue(type);
	final array = input.destination + '_array';
	final index = input.destination + '_index';
	final payload = input.destination + '_payload';
	final offset = input.destination + '_offset';
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
		+ ');'];
	for (line in input.renderValue(input.receiver, array, indent + '  '))
		lines.push(line);
	for (line in input.renderValue(input.index, index, indent + '  '))
		lines.push(line);
	lines.push(indent
		+ '  if ('
		+ array
		+ '.get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument("array read has no array");');
	lines.push(indent + '  const auto ' + payload + ' = ' + array + '.get().asManaged().as<hxhx::managed::ArrayPayload>();');
	// The native index consumes null as zero without changing the rooted source value.
	lines.push(indent + '  const auto ' + offset + ' = ' + CppManagedInteger.numericValue(input.indexType, index + '.get()') + ';');
	lines.push(indent
		+ '  '
		+ input.destination
		+ '.set('
		+ offset
		+ ' < 0 || static_cast<std::size_t>('
		+ offset
		+ ') >= '
		+ payload
		+ '->size() ? '
		+ absent
		+ ' : '
		+ CppManagedArrayElement.read(type, payload + '->read(static_cast<std::size_t>(' + offset + '))')
		+ ');');
	lines.push(indent + '}');
	return lines;
}
