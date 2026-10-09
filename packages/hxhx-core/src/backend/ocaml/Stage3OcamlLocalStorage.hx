package backend.ocaml;

/**
	Convert one local write from exact typed facts. Dynamic uses Obj.t, with a
	separate Boolean box so true remains distinct from integer 1. The rendered
	operand occurs once; this boundary never evaluates or reconstructs source.
 */
function store(write:TypedBackendLocalWrite, rendered:String):String {
	if (!write.binding.getType().isDynamic())
		return rendered;
	final carrier = if (write.sourceType.getSemanticKey() == "primitive:Bool") {
		OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ExactBool;
	} else if (write.sourceType.isDynamic()) {
		OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.DynamicValue;
	} else {
		OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ConcreteValue;
	};
	return OcamlDynamicOperatorLowering.callArgument("Dynamic", carrier, rendered);
}

/** Read the old value before the right operand, then use the existing Dynamic operation. */
function compound(write:TypedBackendLocalWrite, op:String, left:String, right:String, names:Stage3OcamlLocalNames):String {
	if (!write.binding.getType().isDynamic() || !StringTools.endsWith(op, "=") || op == "=")
		throw "Dynamic compound storage requires an exact Dynamic destination and assignment operator";
	final leftName = names.internalName("__hx_storage_left");
	final rightName = names.internalName("__hx_storage_right");
	final operation = OcamlDynamicOperatorLowering.binary(op.substr(0, op.length - 1), DynamicValue, DynamicValue, true, true, leftName, rightName);
	if (operation == null)
		throw "unsupported Dynamic compound storage operation: " + op;
	return "(let " + leftName + " = (" + left + ") in let " + rightName + " = (" + store(write, right) + ") in " + operation + ")";
}
