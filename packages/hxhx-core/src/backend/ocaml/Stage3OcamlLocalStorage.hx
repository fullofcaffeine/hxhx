package backend.ocaml;

/**
	Convert one local write from exact typed facts. Dynamic uses Obj.t, with a
	separate Boolean box so true remains distinct from integer 1. The rendered
	operand occurs once; this boundary never evaluates or reconstructs source.
	A Dynamic source entering a Bool local uses the checked inverse conversion.
	A nullable Int, Float, or Bool destination uses the shared carrier conversion.
 */
function store(write:TypedBackendLocalWrite, rendered:String, names:Null<Stage3OcamlLocalNames>):String {
	if (Stage3OcamlNullablePrimitive.innerPrimitive(write.binding.getType()) != null)
		return Stage3OcamlValueConversion.convert(write.sourceType, write.binding.getType(), rendered, names);
	if (write.binding.getType().getSemanticKey() == "primitive:Bool" && write.sourceType.isDynamic())
		return "HxDynamic.booleanValue (" + rendered + ")";
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
	return "(let "
		+ leftName
		+ " = ("
		+ left
		+ ") in let "
		+ rightName
		+ " = ("
		+ store(write, right, names)
		+ ") in "
		+ operation
		+ ")";
}

/**
	Store an already converted value in a mutable local and yield that stored value.

	Haxe `local = value` is an expression whose result is the assigned value.
	Statement assignments use their own unit-returning form; this form serves an
	assignment inside a larger expression. Inlined abstract operators produce
	such assignments: `counter++` on a `haxe.Int32` local expands to a body that
	writes `this = clamp(this)` back to `counter`. Earlier that value-position
	write rendered as the `(Obj.magic 0)` placeholder, so the increment was lost.
	`ident` is the OCaml `ref` cell; `stored` occurs once and already has the
	local's representation.
 */
function assignValue(ident:String, stored:String, names:Stage3OcamlLocalNames):String {
	if (names == null)
		throw "OCaml local assignment value requires its exact local naming owner";
	final value = names.internalName("__hx_assigned");
	return "(let " + value + " = (" + stored + ") in (" + ident + " := " + value + "; " + value + "))";
}

/**
	Widen an Int operand stored in a `Float` local, as Haxe does for `f = 3`.

	OCaml keeps `int` and `float` apart, so storing the Int literal `3` in a
	`float ref` fails to compile. Only an exact, non-nullable `Float`
	destination with an operand known to be Int is widened; every other
	assignment keeps its rendered value.
 */
function widenIntToFloat(destination:Null<TyType>, operandIsInt:Bool, rendered:String):String {
	if (!operandIsInt || destination == null || destination.isNullable())
		return rendered;
	return TyAliasExpansion.reveal(destination).getSemanticKey() == "primitive:Float" ? "float_of_int (" + rendered + ")" : rendered;
}
