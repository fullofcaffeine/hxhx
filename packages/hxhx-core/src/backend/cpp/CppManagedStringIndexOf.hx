package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** Select only the standard String search declaration; user methods keep ordinary dispatch. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getModulePath() == "String"
		&& declaration.getOwner().getCanonicalName() == "String"
		&& declaration.getIdentity().getCanonicalKey() == "String#instance:indexOf(required:primitive:String,optional:primitive:Int)->primitive:Int#0";
}

/** Require the exact receiver, argument and result facts before selecting native search. */
function require(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):Void {
	if (!selects(call))
		throw "managed String.indexOf requires its exact standard declaration";
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	final arguments = call.getCall().arguments;
	final types = call.getProjectedArgumentTypes();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "indexOf"
		|| signature.getArgs().length != 2
		|| signature.getArgs()[0].getSemanticKey() != "primitive:String"
		|| signature.getArgs()[1].getSemanticKey() != "primitive:Int"
		|| signature.getArgOptional().length != 2
		|| signature.getArgOptional()[0]
		|| !signature.getArgOptional()[1]
		|| signature.getArgRest().length != 2
		|| signature.getArgRest()[0]
		|| signature.getArgRest()[1]
		|| signature.getReturnType().getSemanticKey() != "primitive:Int"
		|| arguments.length < 1
		|| arguments.length > 2
		|| types.length != arguments.length
		|| call.getResultType().getSemanticKey() != "primitive:Int"
		|| call.getReceiverType() == null)
		throw "managed String.indexOf requires a String needle, optional Int start and Int result";
	final receiver = CppManagedCallContext.resolveType(context, call.getReceiverType());
	if (!CppManagedValueTransfer.accepts(TyType.fromHintText("String"), receiver))
		throw "managed String.indexOf requires its String receiver";
	for (index in 0...types.length) {
		final applied = CppManagedCallContext.resolveType(context, types[index]);
		final expected = TyType.fromHintText(index == 0 ? "String" : "Null<Int>");
		if (!applied.isNullLiteral() && !CppManagedValueTransfer.accepts(expected, applied))
			throw "managed String.indexOf argument type differs from its standard declaration";
	}
}

/**
	Evaluate and root the receiver, needle and start in source order. Omitted
	starts stay null for the runtime default. Discarded calls retain all effects.
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
	final needle = input.prefix + "needle";
	final start = input.prefix + "start";
	final lines = [indent + "{"];
	for (name in [receiver, needle, start])
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + input.heap + ");");
	for (line in input.renderValue(call.receiver, receiver, indent + "  "))
		lines.push(line);
	for (line in input.renderValue(call.arguments[0], needle, indent + "  "))
		lines.push(line);
	if (call.arguments.length == 2)
		for (line in input.renderValue(call.arguments[1], start, indent + "  "))
			lines.push(line);
	final operation = "hxhx::managed::stringIndexOf(" + receiver + ".get(), " + needle + ".get(), " + start + ".get())";
	lines.push(indent + "  " + (input.destination == null ? "(void)" + operation : input.destination + ".set(" + operation + ")") + ";");
	lines.push(indent + "}");
	return lines;
}
