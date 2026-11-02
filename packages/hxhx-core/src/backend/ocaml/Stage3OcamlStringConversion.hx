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

/**
	Render one non-String operand of a String concatenation (`"n=" + value`).

	Why: OCaml's `^` accepts only `string`. Earlier, an operand whose exact typed
	result was not a primitive the emitter's name heuristics recognized (for
	example `"x" + (i32 + 1)`, which the typer encodes as a cast of an
	`haxe.Int32` temporary to `Int`) was passed to `^` unchanged. The OCaml
	program still compiled because that temporary was declared with a
	placeholder value, and at run time `^` read an integer as a string pointer
	and crashed with SIGSEGV.

	What: return `null` when the exact type is unknown (the caller keeps its
	older rendering) or is `String` (no conversion). Every other exact type goes
	through `convert`, which is the same runtime `Std.string` path used for
	explicit `Std.string(value)` calls.
**/
function concatOperand(type:Null<TyType>, value:String, names:Stage3OcamlLocalNames):Null<String> {
	if (type == null || type.isUnknown() || type.isUnresolved())
		return null;
	if (TyAliasExpansion.reveal(type).getSemanticKey() == "primitive:String")
		return null;
	return convert(type, value, names);
}
