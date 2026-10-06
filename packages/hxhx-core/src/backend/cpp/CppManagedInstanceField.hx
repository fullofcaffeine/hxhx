package backend.cpp;

import backend.cpp.CppManagedClassStorage.CppManagedInstanceMember;

/**
	A field declared as T retains null even when applied to a scalar. This is the
	target storage view, not a change to shared typing. Concrete destinations use
	the existing checked scalar transfer; reference applications already retain null.
 */
function transportType(member:CppManagedInstanceMember):TyType
	return member.storedType;

/** Reading a field retains its receiver while copying the selected stored value. */
function read(input:{
	occurrence:TypedBackendFieldOccurrence,
	member:CppManagedInstanceMember,
	heap:String,
	destination:String,
	renderReceiver:(TypedBackendFieldOccurrence, String, String) -> Array<String>
}, indent:String):Array<String> {
	final member = input.member;
	final root = input.destination + '_instance_receiver';
	final lines = [
		indent + '{',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + root + '(' + input.heap + ');'
	];
	for (line in input.renderReceiver(input.occurrence, root, indent + '  '))
		lines.push(line);
	lines.push(indent
		+ '  '
		+ input.destination
		+ '.set('
		+ root
		+ '.get().asManaged().as<hxhx::managed::InstancePayload>()->read('
		+ member.layout.symbol
		+ ', '
		+ member.slot
		+ '));');
	lines.push(indent + '}');
	return lines;
}

/**
	Update one mutable Int slot after evaluating its receiver once. The receiver
	root keeps the selected instance alive through allocation in its expression.
	Prefix returns the new value; postfix returns the old value. Nullable field
	updates remain excluded until their upstream native failure is resolved.
 */
function update(input:{
	occurrence:TypedBackendFieldOccurrence,
	member:CppManagedInstanceMember,
	op:HxUnaryOperator,
	fixity:HxUnaryFixity,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderReceiver:(TypedBackendFieldOccurrence, String, String) -> Array<String>
}, indent:String):Array<String> {
	final member = input.member;
	if (input.occurrence.getField().getIsStatic() || (input.op != Increment && input.op != Decrement))
		throw 'managed instance update requires an exact increment or decrement';
	if (member.fact.isFinal)
		throw 'managed instance update requires a mutable field';
	final type = transportType(member);
	if (type.getSemanticKey() != 'primitive:Int')
		throw 'managed instance update requires an exact non-nullable Int field';
	final receiver = input.prefix + 'receiver';
	final before = input.prefix + 'before';
	final after = input.prefix + 'after';
	final location = receiver + '.get().asManaged().as<hxhx::managed::InstancePayload>()';
	final slot = member.layout.symbol + ', ' + member.slot;
	final lines = [
		indent + '{',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + receiver + '(' + input.heap + ');'
	];
	for (line in input.renderReceiver(input.occurrence, receiver, indent + '  '))
		lines.push(line);
	lines.push(indent
		+ '  hxhx::managed::Root<hxhx::managed::Value> '
		+ before
		+ '('
		+ input.heap
		+ ', '
		+ location
		+ '->read('
		+ slot
		+ '));');
	lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + after + '(' + input.heap + ');');
	for (line in CppManagedInteger.compute(input.op == Increment ? '+' : '-', type, TyType.fromHintText('Int'), before + '.get()',
		'hxhx::managed::Value::integer(1)', after, input.prefix, indent + '  '))
		lines.push(line);
	lines.push(indent + '  ' + location + '->write(' + slot + ', ' + after + '.get());');
	if (input.destination != null)
		lines.push(indent + '  ' + input.destination + '.set(' + (input.fixity == Postfix ? before : after) + '.get());');
	lines.push(indent + '}');
	return lines;
}

/** Select the field receiver before RHS effects, without retaining a borrowed vector element. */
function write(input:{
	occurrence:TypedBackendFieldOccurrence,
	member:CppManagedInstanceMember,
	value:HxExpr,
	valueType:TyType,
	?casts:CppManagedCastPlan,
	allowFinal:Bool,
	heap:String,
	prefix:String,
	destination:Null<String>,
	compoundOp:Null<String>,
	renderReceiver:(TypedBackendFieldOccurrence, String, String) -> Array<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final member = input.member;
	final storedType = transportType(member);
	if (member.fact.isFinal && (!input.allowFinal || input.compoundOp != null))
		throw 'managed final field writes require their exact constructor receiver';
	if (input.compoundOp == null && !CppManagedValueTransfer.supports(storedType, input.valueType, input.casts))
		throw 'managed instance assignment requires an explicit typed conversion';
	if (input.compoundOp != null)
		CppManagedCompound.requireType(input.compoundOp, storedType, input.valueType);
	final receiver = input.prefix + 'receiver';
	final value = input.prefix + 'value';
	final before = input.prefix + 'before';
	final location = receiver + '.get().asManaged().as<hxhx::managed::InstancePayload>()';
	final slot = member.layout.symbol + ', ' + member.slot;
	final lines = [indent + '{',
		indent
		+ '  hxhx::managed::Root<hxhx::managed::Value> '
		+ receiver
		+ '('
		+ input.heap
		+ '), '
		+ value
		+ '('
		+ input.heap
		+ ');'];
	for (line in input.renderReceiver(input.occurrence, receiver, indent + '  '))
		lines.push(line);
	if (input.compoundOp != null)
		lines.push(indent
			+ '  hxhx::managed::Root<hxhx::managed::Value> '
			+ before
			+ '('
			+ input.heap
			+ ', '
			+ location
			+ '->read('
			+ slot
			+ '));');
	for (line in input.renderValue(input.value, value, indent + '  '))
		lines.push(line);
	if (input.compoundOp == null)
		for (line in CppManagedValueTransfer.convertRoot(storedType, input.valueType, value, indent + '  ', input.casts))
			lines.push(line);
	if (input.compoundOp != null)
		for (line in CppManagedCompound.compute(input.compoundOp, storedType, input.valueType, before
			+ '.get()', value
			+ '.get()', value,
			input.prefix
			+ 'compute_', indent
			+ '  '))
			lines.push(line);
	lines.push(indent + '  ' + location + '->write(' + slot + ', ' + value + '.get());');
	if (input.destination != null)
		lines.push(indent + '  ' + input.destination + '.set(' + value + '.get());');
	lines.push(indent + '}');
	return lines;
}
