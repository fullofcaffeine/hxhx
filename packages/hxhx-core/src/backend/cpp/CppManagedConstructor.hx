package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** An exact authored constructor body and its allocated program entry. */
typedef CppManagedConstructorTarget = {
	final projection:TypedBackendFunctionProjection;
	final symbol:String;
	final application:CppManagedFunctionApplication;
}

/**
	Evaluate and root constructor arguments before allocating the instance.
	Execute the complete typed Void body with a hidden receiver, then publish the
	constructed value. A thrown constructor leaves the destination untouched;
	source effects that published this elsewhere still retain that same allocation.
 */
function render(input:{
	occurrence:TypedBackendConstructorOccurrence,
	classes:CppManagedClassStorage,
	?context:CppManagedEnclosingApplication,
	?casts:CppManagedCastPlan,
	resolve:String->CppManagedConstructorTarget,
	heap:String,
	destination:String,
	?receiver:String,
	valueType:HxExpr->TyType,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	if (input.classes == null || input.resolve == null)
		throw 'managed construction requires program-owned storage and callable targets';
	if (input.occurrence.getIsSuperCall() != (input.receiver != null))
		throw 'parent construction requires existing receiver transport';
	final projection = input.classes.requireConstructor(input.occurrence, input.context);
	final application = input.classes.constructorApplication(input.occurrence, input.context);
	final target = input.resolve(application.identity);
	if (target == null
		|| target.projection != projection
		|| target.application.identity != application.identity
		|| !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(target.symbol))
		throw 'managed construction resolved another constructor body';
	target.application.assertCurrent();
	final type = CppManagedCallContext.resolveType(input.context, input.occurrence.getConstructedType());
	final plan = new CppManagedStoragePlan(projection, input.classes, application);
	final abi = plan.requireFunction(Root(projection)).abi;
	final abstractReceiver = plan.abstractReceiverType != null;
	if (abi.result != NoResult || !abi.getHiddenParameters().contains(abstractReceiver ? ReceiverCell : ReceiverValue))
		throw 'managed constructor entry requires Void and explicit receiver transport';
	final arguments = input.occurrence.getArguments();
	final slots = input.occurrence.requireArgumentBinding().getSlots();
	final parameters = abi.getParameters();
	final declared = abi.signature.getFunctionParameters();
	final lines = [indent + '{'];
	final parentReceiver = input.destination + '_parent_receiver';
	if (input.receiver != null) {
		if (abstractReceiver)
			throw 'parent construction requires an ordinary class receiver';
		lines.push(indent
			+ '  hxhx::managed::Root<hxhx::managed::Value> '
			+ parentReceiver
			+ '('
			+ input.heap
			+ ', '
			+ input.receiver
			+ ');');
	}
	final roots = new Array<String>();
	// Evaluate supplied operands in authored order, independently of skipped slots.
	// Each root stays alive through all later effects and through construction.
	for (sourceIndex in 0...arguments.length) {
		final matches = [
			for (index in 0...slots.length)
				if (switch slots[index] {
						case Supplied(selected): selected == sourceIndex;
						case _: false;
					}) index
		];
		if (matches.length != 1)
			throw 'managed constructor argument requires one selected parameter';
		final parameter = parameters[matches[0]];
		final argument = arguments[sourceIndex];
		final sourceType = input.valueType(argument);
		final sourceParameter = HxFunctionDecl.getArgs(projection.requireSemanticDeclaration().getSourceDeclaration())[parameter.slot];
		if (sourceType.isNullLiteral()
			&& !HxFunctionArg.getIsOptional(sourceParameter)
			&& !CppManagedValueTransfer.retainsNull(parameter.type, input.casts))
			throw 'managed constructor literal null requires a nullable or question-mark parameter';
		final acceptedType = declared[parameter.slot].isOptional
			&& parameter.storage == RootedParameter
			&& !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type;
		if (!CppManagedValueTransfer.supports(acceptedType, sourceType, input.casts))
			throw 'managed constructor argument requires an explicit typed conversion';
		final root = input.destination + '_constructor_arg' + sourceIndex;
		lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + root + '(' + input.heap + ');');
		for (line in input.renderValue(argument, root, indent + '  '))
			lines.push(line);
		for (line in CppManagedValueTransfer.convertRoot(acceptedType, sourceType, root, indent + '  ', input.casts))
			lines.push(line);
		roots.push(root);
	}
	final transported = [
		for (parameter in parameters)
			switch slots[parameter.slot] {
				case Omitted:
					if (!declared[parameter.slot].isOptional || parameter.storage != RootedParameter)
						throw 'managed constructor omission requires optional rooted transport';
					'hxhx::managed::Value()';
				case Supplied(sourceIndex):
					final value = roots[sourceIndex] + '.get()';
					parameter.storage == RootedParameter ? value : CppManagedLeaf.read(parameter.type, value);
				case RestElements(_) | RestSpread(_):
					throw 'managed constructor rest arguments require explicit container transport';
			}
	];
	final instance = input.destination + '_instance';
	if (input.receiver != null) {
		lines.push(indent + '  ' + target.symbol + '(' + [input.heap, parentReceiver + '.get()'].concat(transported).join(', ') + ');');
		lines.push(indent + '}');
		return lines;
	}
	if (abstractReceiver) {
		lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> ' + instance + '(' + input.heap + ');');
		lines.push(indent + '  ' + input.heap + '.allocateInto(' + instance + ', hxhx::managed::CellWriteMode::Replaceable);');
		lines.push(indent + '  ' + target.symbol + '(' + [input.heap, instance + '.get()'].concat(transported).join(', ') + ');');
		// Copy the final value; surviving closures still own this same receiver cell.
		lines.push(indent + '  ' + input.destination + '.set(' + instance + '.get()->read());');
		// Generic constructor cells retain null. Only this caller's written
		// destination selects scalar storage; escaped cells are never converted.
		final published = input.classes.casts.appliedAbstractStorage(input.occurrence.getConstructedType(), type);
		final stored = input.classes.casts.representationType(published);
		final produced = input.classes.casts.representationType(application.storedBackingType);
		for (line in CppManagedValueTransfer.convertRoot(stored, produced, input.destination, indent + '  '))
			lines.push(line);
		lines.push(indent + '}');
		return lines;
	}
	final layout = input.classes.requireType(type);
	lines.push(indent
		+ '  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::InstancePayload>> '
		+ instance
		+ '('
		+ input.heap
		+ ');');
	lines.push(indent + '  ' + input.heap + '.allocateInto(' + instance + ', ' + layout.symbol + ', std::vector<hxhx::managed::Value>{'
		+ input.classes.defaults(type).join(', ') + '});');
	final value = 'hxhx::managed::Value::managed(' + instance + '.get())';
	lines.push(indent + '  ' + target.symbol + '(' + [input.heap, value].concat(transported).join(', ') + ');');
	lines.push(indent + '  ' + input.destination + '.set(' + value + ');');
	lines.push(indent + '}');
	return lines;
}
