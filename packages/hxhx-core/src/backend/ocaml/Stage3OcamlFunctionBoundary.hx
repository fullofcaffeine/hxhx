package backend.ocaml;

/**
	Pass a typed function where `haxe.Constraints.Function` is expected.

	A `Function` value is called through the Dynamic convention:
	`Reflect.callMethod(o, f, args)` applies it to the `Obj.t` elements of
	`args`, whatever their runtime category. A typed closure cannot receive
	those directly. A listener such as `function(d) Sys.println("listener " +
	d)` is typed `String -> Void` (upstream infers String for `d` too), and an
	Int arriving in its `string` slot crashed the native program.

	The adapter wraps the closure so each `Obj.t` input becomes the parameter's
	carrier:
	- a String parameter receives the value's text, and null stays null. Eval
	  prints `listener 7` for an Int, and hxcpp converts a Dynamic in a String
	  slot the same way;
	- Int, Bool and nullable primitive parameters use the checked conversions of
	  `Stage3OcamlValueConversion`, which raise a catchable error for a value of
	  another category instead of reading its bits;
	- Dynamic and every other parameter type receive the value as before.

	The result is boxed for the Dynamic convention (a Bool gets its box), and a
	Void function returns null. A function with optional or rest parameters
	keeps the old raw closure.
**/
function adapt(actual:TyType, value:String, names:Null<Stage3OcamlLocalNames>):Null<String> {
	if (names == null || actual == null || !actual.isFunction() || actual.hasUnknownComponent())
		return null;
	final parameters = actual.getFunctionParameters();
	for (parameter in parameters)
		if (parameter.isOptional || parameter.isRest)
			return null;
	final closure = names.internalName("__hx_function_value");
	final inputs = [
		for (index in 0...parameters.length)
			names.internalName("__hx_function_input_" + index)
	];
	final arguments = [
		for (index in 0...parameters.length)
			"(" + input(parameters[index].type, inputs[index], names) + ")"
	];
	final call = closure + (arguments.length == 0 ? " ()" : " " + arguments.join(" "));
	final returned = result(actual.getFunctionReturn(), call);
	if (returned == null)
		return null;
	return "(let "
		+ closure
		+ " = ("
		+ value
		+ ") in Obj.repr (fun "
		+ (inputs.length == 0 ? "()" : inputs.join(" "))
		+ " -> "
		+ returned
		+ "))";
}

/** Convert one `Obj.t` input into the carrier of a parameter of `type`. */
function input(type:TyType, value:String, names:Stage3OcamlLocalNames):String {
	final revealed = TyAliasExpansion.reveal(type);
	if (revealed.isDynamic())
		return value;
	if (!revealed.isNullable() && revealed.getSemanticKey() == "primitive:String")
		return "(if HxRuntime.is_null "
			+ value
			+ " then (Obj.magic HxRuntime.hx_null : string) else HxDynamic.toStdString "
			+ value
			+ ")";
	if (Stage3OcamlNullablePrimitive.innerPrimitive(revealed) != null)
		return Stage3OcamlValueConversion.convert(TyType.fromHintText("Dynamic"), revealed, value, names);
	return switch revealed.getSemanticKey() {
		case "primitive:Int" | "primitive:Bool": Stage3OcamlValueConversion.convert(TyType.fromHintText("Dynamic"), revealed, value, names);
		case _: "Obj.obj " + value;
	};
}

/** Box a result for the Dynamic convention, or null when this carrier has no conversion here. */
function result(type:TyType, call:String):Null<String> {
	final revealed = TyAliasExpansion.reveal(type);
	if (revealed.isVoid())
		return "(ignore (" + call + "); HxRuntime.hx_null)";
	if (revealed.isDynamic())
		return call;
	return switch revealed.getSemanticKey() {
		case "primitive:Bool": "HxRuntime.box_bool (" + call + ")";
		case _: "Obj.repr (" + call + ")";
	};
}
