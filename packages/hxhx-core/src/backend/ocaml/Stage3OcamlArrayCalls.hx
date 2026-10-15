package backend.ocaml;

/** Only these declared Array operations use this native call adapter. */
function supports(method:String):Bool {
	return switch method {
		case "map" | "join" | "push" | "copy" | "concat" | "slice" | "splice" | "filter": true;
		case _: false;
	};
}

/**
	Render selected Array operations through the shared array runtime.
	The exact occurrence supplies receiver types before ordinary instance-call
	adaptation discards them. Bind receiver and argument in Haxe evaluation order;
	OCaml function application alone does not guarantee that order.
 */
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	metal:Bool,
	autoMetal:Bool,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames,
	mark:String->Void
}):Null<String> {
	final occurrence = input.occurrence;
	final call = occurrence.getCall();
	if (occurrence.getDeclaration().getOwner().getCanonicalName() != "Array" || !supports(call.method))
		return null;
	final receiverType = occurrence.getReceiverType();
	if (receiverType == null
		|| receiverType.getNominalIdentity() == null
		|| receiverType.getNominalIdentity().getCanonicalName() != "Array"
		|| receiverType.getTypeArguments().length != 1)
		throw "selected OCaml array call requires its exact Array receiver type";
	final expectedCount = switch call.method {
		case "copy": 0;
		case "splice": 2;
		case "slice": call.arguments.length == 1 ? 1 : 2;
		case _: 1;
	};
	if (call.arguments.length != expectedCount || input.names == null)
		throw "selected OCaml array call requires its argument and local naming owner";
	final strings = receiverType.getTypeArguments()[0].getSemanticKey() == "primitive:String";
	final autoTyped = input.autoMetal && strings;
	final receiver = input.names.internalName("__hx_array_receiver");
	// Portable producers such as map use an erased array ABI. The checked Array
	// declaration and element type permit the native operation's typed view of
	// that same container; no slots or aliases change at this boundary.
	final runtimeReceiver = input.metal ? receiver : "(Obj.magic " + receiver + ")";
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_array_argument_" + index)
	];
	final argument = arguments.length == 0 ? "" : arguments[0];
	final operation = switch (call.method) {
		case "map": if (autoTyped) input.mark("array_map_typed"); input.metal || autoTyped ? "HxBootArray.map (" + receiver + ") (" + argument + ")" : "HxBootArray.map_dyn (Obj.magic (" + receiver + ")) (Obj.repr (" + argument + "))";
		case "join":
			if (input.metal && !strings)
				throw "stage3 emitter: metal profile unsupported semantics: Array.join requires Array<String> receiver";
			if (autoTyped)
				input.mark("array_join_typed");
			if (input.metal || autoTyped) "HxBootArray.join_strict (" + receiver + ") (" + argument + ") (fun (s : string) -> s)"; else if (strings)
				"HxBootArray.join ("
				+ receiver + ") (" + argument + ") (fun (s : string) -> s)"; else "HxBootArray.join_dyn (Obj.magic (" + receiver + ")) (" + argument + ")";
		case "push":
			final stored = receiverType.getTypeArguments()[0].isDynamic() ? "(Obj.magic ("
				+ Stage3OcamlObjects.store(occurrence.getProjectedArgumentTypes()[0], argument)
				+ "))" : argument;
			"HxArray.push " + runtimeReceiver + " " + stored;
		case "copy": "HxArray.copy " + runtimeReceiver;
		case "concat": "HxArray.concat " + runtimeReceiver + " " + argument;
		case "slice":
			arguments.length == 1 ? "HxArray.slice_default " + runtimeReceiver + " " + argument : "HxArray.slice "
				+ runtimeReceiver
				+ " "
				+ arguments.join(" ");
		case "splice": "HxArray.splice " + runtimeReceiver + " " + arguments.join(" ");
		case "filter": "HxArray.filter " + runtimeReceiver + " " + argument;
		case _: throw "unexpected selected array operation";
	};
	final result = call.method == "map"
		&& !input.metal ? Stage3OcamlArrays.retainStringifier(occurrence.getResultType(), operation, input.names) : operation;
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	for (index in 0...arguments.length)
		bindings.push("let " + arguments[index] + " = (" + input.emit(call.arguments[index]) + ") in ");
	return "(" + bindings.join("") + result + ")";
}
