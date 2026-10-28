package backend.ocaml;

/** String operations whose bounds or nullable results use the shared runtime. */
function supports(method:String):Bool {
	return switch method {
		case "indexOf" | "lastIndexOf" | "substr" | "substring" | "charAt" | "charCodeAt": true;
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
	final characterRead = call.method == "charAt" || call.method == "charCodeAt";
	if (characterRead && call.arguments.length != 1)
		throw "selected OCaml character call requires one index";
	final receiver = input.names.internalName("__hx_string_receiver");
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_string_argument_" + index)
	];
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	final argumentTypes = occurrence.getArgumentTypes();
	for (index in 0...arguments.length) {
		// charAt and charCodeAt take a required index; the other slots are optional
		// ints that recognize the sentinel bits, so a nullable Int carrier passes through.
		final rendered = input.emit(call.arguments[index]);
		final nullableInt = index < argumentTypes.length
			&& Stage3OcamlNullablePrimitive.innerPrimitive(argumentTypes[index]) == "primitive:Int";
		final value = !nullableInt ? rendered : characterRead ? Stage3OcamlNullablePrimitive.unwrap("primitive:Int",
			rendered) : Stage3OcamlNullablePrimitive.intrinsicOptionalInt(rendered);
		bindings.push("let " + arguments[index] + " = (" + value + ") in ");
	}
	if (call.method == "charCodeAt") {
		// The runtime produces an Int or the canonical null sentinel. Restore the
		// Stage3 nullable value view without inspecting bits or unwrapping null;
		// an authored null test must still run before any integer operation.
		return "(" + bindings.join("") + "Obj.magic (HxString.charCodeAt " + receiver + " " + arguments[0] + "))";
	}
	// charAt returns an ordinary String, including "" outside the bounds.
	if (call.method == "charAt")
		return "(" + bindings.join("") + "HxString.charAt " + receiver + " " + arguments[0] + ")";
	// HxString's optional Int ABI recognizes this sentinel before integer use.
	// This is a representation boundary, not an unchecked source-type conversion.
	if (arguments.length == 1)
		arguments.push("(Obj.magic HxRuntime.hx_null)");
	return "(" + bindings.join("") + "HxString." + call.method + " " + receiver + " " + arguments.join(" ") + ")";
}
