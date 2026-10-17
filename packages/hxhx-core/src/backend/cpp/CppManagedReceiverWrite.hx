package backend.cpp;

/**
	Replace an abstract constructor's receiver only after the right side succeeds.
	The selected cell and old compound value remain rooted across allocating effects.
	The caller validates the exact lexical receiver; source names cannot select cells.
 */
function render(input:{
	reference:String,
	type:TyType,
	value:HxExpr,
	valueType:TyType,
	?casts:CppManagedCastPlan,
	?compoundOp:String,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	if (input.compoundOp == null) {
		if (!CppManagedValueTransfer.supports(input.type, input.valueType, input.casts))
			throw 'managed receiver assignment requires an explicit typed conversion';
	} else
		CppManagedCompound.requireType(input.compoundOp, input.type, input.valueType);
	final cell = input.prefix + 'cell';
	final assigned = input.prefix + 'assigned';
	final before = input.prefix + 'before';
	final lines = [indent + '{',
		indent
		+ '  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> '
		+ cell
		+ '('
		+ input.heap
		+ ', '
		+ input.reference
		+ ');',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + assigned + '(' + input.heap + ');'
	];
	if (input.compoundOp != null)
		lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + before + '(' + input.heap + ', ' + cell + '.get()->read());');
	for (line in input.renderValue(input.value, assigned, indent + '  '))
		lines.push(line);
	if (input.compoundOp == null)
		for (line in CppManagedValueTransfer.convertRoot(input.type, input.valueType, assigned, indent + '  ', input.casts))
			lines.push(line);
	if (input.compoundOp != null)
		for (line in CppManagedCompound.compute(input.compoundOp, input.type, input.valueType, before
			+ '.get()', assigned
			+ '.get()', assigned,
			input.prefix
			+ 'compound_', indent
			+ '  '))
			lines.push(line);
	lines.push(indent + '  ' + cell + '.get()->write(' + assigned + '.get());');
	if (input.destination != null)
		lines.push(indent + '  ' + input.destination + '.set(' + assigned + '.get());');
	lines.push(indent + '}');
	return lines;
}
