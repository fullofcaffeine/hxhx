package backend.ocaml;

import backend.ocaml.OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier;

/** Pass the original typed value to runtime string conversion exactly once. */
function convert(type:TyType, value:String, names:Stage3OcamlLocalNames):String {
	if (type == null || type.isUnknown() || type.isUnresolved())
		throw "OCaml string conversion requires an exact argument type";
	final concrete = type.unwrapNull();
	final identity = concrete.getNominalIdentity();
	if (identity != null && identity.getCanonicalName() == "Array") {
		final arguments = concrete.getTypeArguments();
		if (arguments.length != 1 || names == null)
			throw "OCaml array string conversion requires its element type and local names";
		// Bind the array once before checking null. The callback uses the original
		// element type, so nested arrays and Boolean values retain their meaning.
		final array = names.internalName("__hx_string_array");
		final element = names.internalName("__hx_string_element");
		return "(let " + array + " = (" + value + ") in if HxRuntime.is_null (Obj.repr " + array + ") then \"null\" else HxArray.toString " + array
			+ " (fun " + element + " -> " + convert(arguments[0], element, names) + "))";
	}
	if (type.isNullable() && type.unwrapNull().getSemanticKey() == "primitive:Bool")
		return "HxRuntime.nullable_bool_toStdString (Obj.repr (" + value + "))";
	final carrier:OcamlDynamicArgumentCarrier = type.getSemanticKey() == "primitive:Bool" ? ExactBool : type.isDynamic() ? DynamicValue : ConcreteValue;
	return "HxDynamic.toStdString (" + OcamlDynamicOperatorLowering.callArgument("Dynamic", carrier, value) + ")";
}
