package backend.cpp;

/**
	Update one exact mutable Int static field and publish the selected old/new value.
	Program storage remains rooted for the request. Reading and writing its slot
	uses no source callback or allocation; integer arithmetic owns wraparound.
 */
function render(input:{
	field:TypedBackendFieldOccurrence,
	storage:CppManagedStaticStorage,
	op:HxUnaryOperator,
	fixity:HxUnaryFixity,
	heap:String,
	prefix:String,
	destination:Null<String>
}, indent:String):Array<String> {
	if (!input.field.getField().getIsStatic() || (input.op != Increment && input.op != Decrement))
		throw 'managed static update requires an exact increment or decrement';
	CppManagedInteger.resultType('+', input.field.getType(), TyType.fromHintText('Int'));
	final member = input.storage.member(input.field, true);
	final selected = input.prefix + 'selected';
	final before = input.prefix + 'before';
	final after = input.prefix + 'after';
	final lines = [indent + '{',
		indent
		+ '  const auto '
		+ selected
		+ ' = '
		+ input.heap
		+ '.requireStatic<'
		+ input.storage.nativeName
		+ '>();',
		indent
		+ '  hxhx::managed::Root<hxhx::managed::Value> '
		+ before
		+ '('
		+ input.heap
		+ ', '
		+ selected
		+ '->'
		+ member
		+ '.read());',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + after + '(' + input.heap + ');'
	];
	for (line in CppManagedInteger.compute(input.op == Increment ? '+' : '-', input.field.getType(), TyType.fromHintText('Int'), before + '.get()',
		'hxhx::managed::Value::integer(1)', after, input.prefix, indent + '  '))
		lines.push(line);
	lines.push(indent + '  ' + selected + '->' + member + '.write(' + after + '.get());');
	if (input.destination != null)
		lines.push(indent
			+ '  '
			+ input.destination
			+ '.set('
			+ (input.fixity == Postfix ? 'hxhx::managed::Value::integer('
				+ CppManagedInteger.numericValue(input.field.getType(), before + '.get()')
				+ ')' : after
				+ '.get()')
			+ ');');
	lines.push(indent + '}');
	return lines;
}
