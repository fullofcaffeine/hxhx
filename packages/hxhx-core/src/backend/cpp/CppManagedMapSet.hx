package backend.cpp;

/** Only the indexed standard Map declaration owns this native mutation boundary. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getOwner().getCanonicalName() == "haxe.ds.Map"
		&& declaration.getModulePath() == "haxe.ds.Map"
		&& declaration.getSignature().getName() == "set";
}

/** Check the declaration's own K/V binders together with the applied call and Void result. */
function require(call:TypedBackendInstanceCallOccurrence, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors, ?casts:CppManagedCastPlan):Void {
	if (!selects(call))
		throw "managed Map.set requires its exact standard declaration";
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getArgs().length != 2
		|| signature.getArgOptional().length != 2
		|| signature.getArgRest().length != 2
		|| signature.getArgOptional().indexOf(true) >= 0
		|| signature.getArgRest().indexOf(true) >= 0
		|| call.getReceiverType() == null
		|| call.getCall().arguments.length != 2
		|| call.getArgumentTypes().length != 2
		|| !call.getResultType().isVoid())
		throw "managed Map.set requires its exact ordinary instance signature";
	for (index in 0...2) {
		final parameter = signature.getArgs()[index].getTypeParameterIdentity();
		if (parameter == null || !parameter.equals(TyTypeParameterId.nominal(declaration.getOwner(), index, parameter.getName())))
			throw "managed Map.set requires the owning Map key and value parameters";
	}
	final storage = CppManagedMapStorage.select(call.getReceiverType(), classes, enums);
	if (storage.keyType.getSemanticKey() != call.getArgumentTypes()[0].getSemanticKey()
		|| !CppManagedValueTransfer.supports(storage.valueType, call.getArgumentTypes()[1], casts))
		throw "managed Map.set requires compatible applied key and value types";
}

/** Public set and comprehension insertion share one rooted mutation implementation. */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	?casts:CppManagedCastPlan,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.call, input.classes, input.enums, input.casts);
	if (input.destination != null)
		throw "Void Map.set cannot publish a value";
	final call = input.call.getCall();
	return CppManagedMapInsert.render({
		map: call.receiver,
		key: call.arguments[0],
		value: call.arguments[1],
		mapType: input.call.getReceiverType(),
		keyType: input.call.getArgumentTypes()[0],
		valueType: input.call.getArgumentTypes()[1],
		classes: input.classes,
		enums: input.enums,
		casts: input.casts,
		heap: input.heap,
		prefix: input.prefix,
		renderValue: input.renderValue
	}, indent);
}
