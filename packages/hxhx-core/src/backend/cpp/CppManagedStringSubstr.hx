package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** Bind the standard String declaration without recognizing same-named user methods. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getModulePath() == "String"
		&& declaration.getOwner().getCanonicalName() == "String"
		&& declaration.getIdentity().getCanonicalKey() == "String#instance:substr(required:primitive:Int,optional:primitive:Int)->primitive:String#0";
}

/** Validate retained call facts before admitting the native string operation. */
function require(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):Void {
	if (!selects(call))
		throw "managed String.substr requires its exact standard declaration";
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	final arguments = call.getCall().arguments;
	final types = call.getProjectedArgumentTypes();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "substr"
		|| signature.getArgs().length != 2
		|| signature.getArgs()[0].getSemanticKey() != "primitive:Int"
		|| signature.getArgs()[1].getSemanticKey() != "primitive:Int"
		|| signature.getArgOptional().length != 2
		|| signature.getArgOptional()[0]
		|| !signature.getArgOptional()[1]
		|| signature.getArgRest().length != 2
		|| signature.getArgRest()[0]
		|| signature.getArgRest()[1]
		|| signature.getReturnType().getSemanticKey() != "primitive:String"
		|| arguments.length < 1
		|| arguments.length > 2
		|| types.length != arguments.length
		|| call.getResultType().getSemanticKey() != "primitive:String"
		|| call.getReceiverType() == null)
		throw "managed String.substr requires an Int position, optional Int length and String result";
	final receiver = CppManagedCallContext.resolveType(context, call.getReceiverType());
	if (!CppManagedValueTransfer.accepts(TyType.fromHintText("String"), receiver))
		throw "managed String.substr requires its String receiver";
	for (type in types) {
		final applied = CppManagedCallContext.resolveType(context, type);
		if (!applied.isNullLiteral() && !CppManagedValueTransfer.accepts(TyType.fromHintText("Null<Int>"), applied))
			throw "managed String.substr requires Int or null bounds";
	}
}

/**
	Root each operand before evaluating the next one. The runtime consumes the
	completed values; an omitted length stays null rather than becoming zero.
	Discarded calls still execute the operation and preserve operand failures.
 */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	?context:CppManagedEnclosingApplication,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.call, input.context);
	final call = input.call.getCall();
	final receiver = input.prefix + "receiver";
	final position = input.prefix + "position";
	final length = input.prefix + "length";
	final lines = [indent + "{"];
	for (name in [receiver, position, length])
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + input.heap + ");");
	for (line in input.renderValue(call.receiver, receiver, indent + "  "))
		lines.push(line);
	for (line in input.renderValue(call.arguments[0], position, indent + "  "))
		lines.push(line);
	if (call.arguments.length == 2)
		for (line in input.renderValue(call.arguments[1], length, indent + "  "))
			lines.push(line);
	final operation = "hxhx::managed::stringSubstr(" + receiver + ".get(), " + position + ".get(), " + length + ".get())";
	lines.push(indent + "  " + (input.destination == null ? "(void)" + operation : input.destination + ".set(" + operation + ")") + ";");
	lines.push(indent + "}");
	return lines;
}
