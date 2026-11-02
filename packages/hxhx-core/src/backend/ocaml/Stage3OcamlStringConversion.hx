package backend.ocaml;

import backend.ocaml.OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier;

/**
	Whether a checked String-concatenation operand of this type is a Bool or
	`Null<Bool>`. Such an operand must reach `convert` with its type: an OCaml
	`bool` and `int` share one runtime shape, so the runtime alone would print
	`true` as `1` (haxe_ocaml-agc6n, haxe_ocaml-caxgt).
**/
function isBoolText(type:Null<TyType>, ?underlying:String->Null<TyType>):Bool
	return boolTextType(type, underlying) != null;

/**
	The Bool or `Null<Bool>` type whose text a value of `type` has, or null.
	`underlying` returns the backing type of a generated abstract by its
	identity, so `abstract Flag(Bool)` (and `Null<Flag>`) print like a Bool.
**/
function boolTextType(type:Null<TyType>, ?underlying:String->Null<TyType>):Null<TyType> {
	if (type == null || type.isUnknown() || type.isUnresolved())
		return null;
	var current = type.unwrapNull();
	final seen:Map<String, Bool> = [];
	while (current.getSemanticKey() != "primitive:Bool") {
		final identity = current.getNominalIdentity();
		final backing = identity == null || underlying == null ? null : underlying(identity.getCanonicalName());
		if (backing == null || seen.exists(identity.getCanonicalName()))
			return null;
		seen.set(identity.getCanonicalName(), true);
		current = backing.unwrapNull();
	}
	if (current == type.unwrapNull())
		return type;
	return TyType.fromHintText(type.isNullable() ? "Null<Bool>" : "Bool");
}

/** `type`, or Bool / `Null<Bool>` when it is an abstract over Bool. */
function textType(type:TyType, ?underlying:String->Null<TyType>):TyType {
	final boolText = boolTextType(type, underlying);
	return boolText == null ? type : boolText;
}

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
