package backend.ocaml;

/** String operations whose optional bound uses the shared runtime's null convention. */
function supports(method:String):Bool {
	return switch method {
		case "indexOf" | "lastIndexOf" | "substr" | "substring": true;
		case _: false;
	};
}

/**
	Render the selected String declaration before ordinary instance-call adaptation.
	The typed occurrence supplies the receiver and operands; a matching method name
	alone cannot select this runtime. Bind supplied values once in Haxe source order.
	The existing runtime accepts the canonical null sentinel for an omitted bound,
	so zero remains an explicit bound and no receiver is evaluated again for defaults.
 */
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames
}):Null<String> {
	final occurrence = input.occurrence;
	final call = occurrence.getCall();
	if (occurrence.getDeclaration().getOwner().getCanonicalName() != "String" || !supports(call.method))
		return null;
	final receiverType = occurrence.getReceiverType();
	if (receiverType == null || receiverType.unwrapNull().getSemanticKey() != "primitive:String")
		throw "selected OCaml string call requires its exact String receiver type";
	if ((call.arguments.length != 1 && call.arguments.length != 2) || input.names == null)
		throw "selected OCaml string call requires its argument and local naming owner";
	final receiver = input.names.internalName("__hx_string_receiver");
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_string_argument_" + index)
	];
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	for (index in 0...arguments.length)
		bindings.push("let " + arguments[index] + " = (" + input.emit(call.arguments[index]) + ") in ");
	// HxString's optional Int ABI recognizes this sentinel before integer use.
	// This is a representation boundary, not an unchecked source-type conversion.
	if (arguments.length == 1)
		arguments.push("(Obj.magic HxRuntime.hx_null)");
	return "(" + bindings.join("") + "HxString." + call.method + " " + receiver + " " + arguments.join(" ") + ")";
}
