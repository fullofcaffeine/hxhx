package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** Only the standard Array declaration selects this binding; user methods remain ordinary calls. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getModulePath() == "Array"
		&& declaration.getOwner().getCanonicalName() == "Array"
		&& declaration.getIdentity().getCanonicalKey() == "Array#instance:join(required:primitive:String)->primitive:String#0";
}

/** Preserve exact signature and occurrence facts before selecting the applied element formatter. */
function require(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):TyType {
	if (!selects(call))
		throw "managed Array.join requires its exact standard declaration";
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "join"
		|| signature.getArgs().length != 1
		|| signature.getArgs()[0].getSemanticKey() != "primitive:String"
		|| signature.getArgOptional().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest().length != 1
		|| signature.getArgRest()[0]
		|| signature.getReturnType().getSemanticKey() != "primitive:String"
		|| call.getCall().arguments.length != 1
		|| call.getArgumentTypes().length != 1
		|| call.getResultType().getSemanticKey() != "primitive:String"
		|| call.getReceiverType() == null)
		throw "managed Array.join requires one required String separator and a String result";
	final separator = CppManagedCallContext.resolveType(context, call.getArgumentTypes()[0]);
	if (!CppManagedValueTransfer.accepts(TyType.fromHintText("String"), separator))
		throw "managed Array.join requires an applied String separator";
	var receiver = CppManagedCallContext.resolveType(context, call.getReceiverType());
	CppManagedClosureAbi.assertComplete(receiver);
	while (receiver.getNullableInner() != null)
		receiver = receiver.getNullableInner();
	if (receiver.getNominalIdentity() == null
		|| receiver.getNominalIdentity().getCanonicalName() != "Array"
		|| receiver.getTypeArguments().length != 1)
		throw "managed Array.join requires its applied Array receiver";
	final element = receiver.getTypeArguments()[0];
	// Object, aggregate and Float conversion must gain their own complete policy.
	// Reject them during planning instead of printing placeholders for managed references.
	CppManagedStringConversion.requireType(element);
	return element;
}

/**
	Native Array.join checks a null receiver before evaluating the separator.
	Keep the receiver rooted across that evaluation, and treat a null separator as
	empty bytes. Primitive conversion cannot execute Haxe or collect the heap, so
	the payload borrow stays inside the conversion loop. Discarded calls retain all
	operand effects and validation. Object conversion must revisit this borrow rule.
 */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	?context:CppManagedEnclosingApplication,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final element = require(input.call, input.context);
	final call = input.call.getCall();
	final array = input.prefix + "array";
	final separator = input.prefix + "separator";
	final payload = input.prefix + "payload";
	final bytes = input.prefix + "bytes";
	final index = input.prefix + "index";
	final value = input.prefix + "value";
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Value> "
		+ array
		+ "("
		+ input.heap
		+ "), "
		+ separator
		+ "("
		+ input.heap
		+ ");"];
	for (line in input.renderValue(call.receiver, array, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  if ("
		+ array
		+ ".get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument(\"array join has no array\");");
	for (line in input.renderValue(call.arguments[0], separator, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  const std::string "
		+ separator
		+ "Bytes = "
		+ separator
		+ ".get().kind() == hxhx::managed::ValueKind::Null ? std::string() : "
		+ separator
		+ ".get().asString();");
	lines.push(indent + "  const auto " + payload + " = " + array + ".get().asManaged().as<hxhx::managed::ArrayPayload>();");
	lines.push(indent + "  std::string " + bytes + ";");
	lines.push(indent + "  for (std::size_t " + index + " = 0; " + index + " < " + payload + "->size(); ++" + index + ") {");
	lines.push(indent + "    if (" + index + " != 0) " + bytes + " += " + separator + "Bytes;");
	lines.push(indent
		+ "    const auto "
		+ value
		+ " = "
		+ CppManagedArrayElement.read(element, payload + "->read(" + index + ")")
		+ ";");
	lines.push(indent + "    " + bytes + " += " + CppManagedStringConversion.format(element, value) + ";");
	lines.push(indent + "  }");
	if (input.destination != null)
		lines.push(indent + "  " + input.destination + ".set(hxhx::managed::Value::string(" + bytes + "));");
	lines.push(indent + "}");
	return lines;
}
