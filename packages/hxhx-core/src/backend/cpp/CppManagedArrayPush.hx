package backend.cpp;

/** Source spelling cannot select push: the exact standard instance declaration must own the call. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getOwner().getCanonicalName() == 'Array'
		&& declaration.getModulePath() == 'Array'
		&& declaration.getSignature().getName() == 'push';
}

/** Keep declaration arity and applied receiver, argument, and Int result facts together. */
function require(call:TypedBackendInstanceCallOccurrence, ?casts:CppManagedCastPlan):Void {
	if (!selects(call))
		throw 'managed Array.push requires its exact standard declaration';
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getArgs().length != 1
		|| signature.getArgOptional().length != 1
		|| signature.getArgRest().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest()[0]
		|| signature.getReturnType().getSemanticKey() != 'primitive:Int'
		|| call.getReceiverType() == null
		|| call.getCall().arguments.length != 1
		|| call.getArgumentTypes().length != 1
		|| call.getResultType().getSemanticKey() != 'primitive:Int')
		throw 'managed Array.push requires its exact ordinary instance signature';
	final parameter = signature.getArgs()[0].getTypeParameterIdentity();
	if (parameter == null || !parameter.equals(TyTypeParameterId.nominal(declaration.getOwner(), 0, parameter.getName())))
		throw 'managed Array.push requires the owning Array element parameter';
	CppManagedArrayAppend.requireTypes(call.getReceiverType(), call.getArgumentTypes()[0], casts);
}

/** Public calls and comprehension appends share rooted mutation; only public push publishes length. */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	?casts:CppManagedCastPlan,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.call, input.casts);
	final call = input.call.getCall();
	return CppManagedArrayAppend.render({
		array: call.receiver,
		value: call.arguments[0],
		arrayType: input.call.getReceiverType(),
		valueType: input.call.getArgumentTypes()[0],
		casts: input.casts,
		heap: input.heap,
		prefix: input.prefix,
		destination: input.destination,
		renderValue: input.renderValue
	}, indent);
}
