package backend.ocaml;

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
	if (occurrence.getDeclaration().getOwner().getCanonicalName() != "Array" || (call.method != "map" && call.method != "join"))
		return null;
	final receiverType = occurrence.getReceiverType();
	if (receiverType == null
		|| receiverType.getNominalIdentity() == null
		|| receiverType.getNominalIdentity().getCanonicalName() != "Array"
		|| receiverType.getTypeArguments().length != 1)
		throw "selected OCaml array call requires its exact Array receiver type";
	if (call.arguments.length != 1 || input.names == null)
		throw "selected OCaml array call requires its argument and local naming owner";
	final strings = receiverType.getTypeArguments()[0].getSemanticKey() == "primitive:String";
	final autoTyped = input.autoMetal && strings;
	final receiver = input.names.internalName("__hx_array_receiver");
	final argument = input.names.internalName("__hx_array_argument");
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
		case _: throw "unexpected selected array operation";
	};
	return "(let " + receiver + " = (" + input.emit(call.receiver) + ") in let " + argument + " = (" + input.emit(call.arguments[0]) + ") in " + operation
		+ ")";
}
