package backend.ocaml;

/**
	Store a typed function where `haxe.Constraints.Function` is expected.

	A `Function` value is called through the Dynamic convention:
	`Reflect.callMethod(o, f, args)` hands it the `Obj.t` elements of `args`,
	whatever their number and runtime category. A typed closure cannot receive
	those directly. A listener such as `function(d) Sys.println("listener " +
	d)` is typed `String -> Void` (upstream infers String for `d` too), and an
	Int arriving in its `string` slot crashed the native program.

	The adapter wraps the closure in an `HxReflect.makeVarArgs` function that
	receives the whole argument array:
	- More arguments than parameters raise a catchable error, as eval does. A
	  missing argument is null for a reference or nullable parameter, as in
	  eval, and the static default (0, 0.0, false) for a non-null Int, Float or
	  Bool parameter, which cannot hold null natively.
	- A String parameter receives the value's text, and null stays null. Eval
	  prints `listener 7` for an Int, and hxcpp converts a Dynamic in a String
	  slot the same way. Other String operations differ from eval: eval keeps
	  the Int, so `s.length` or `s == "7"` behave differently there.
	- A Float parameter accepts an Int (converted) or a Float; Int, Bool and
	  nullable primitive parameters use the checked conversions of
	  `Stage3OcamlValueConversion`. A value of another category raises a
	  catchable error instead of being read with the wrong bits.
	- Dynamic and every other parameter type receive the value unchanged.
	- The result is boxed for the Dynamic convention (a Bool gets its box), and
	  a Void function returns null.

	A function with optional or rest parameters is rejected at emit time with
	a named error: the adapter has no storage plan for them yet.
**/
function adapt(actual:TyType, value:String, names:Null<Stage3OcamlLocalNames>):Null<String> {
	if (names == null || actual == null || !actual.isFunction() || actual.hasUnknownComponent())
		return null;
	final parameters = actual.getFunctionParameters();
	for (parameter in parameters)
		if (parameter.isOptional || parameter.isRest)
			throw "stage3 emitter: a function with optional or rest parameters cannot be stored as haxe.Constraints.Function yet";
	final closure = names.internalName("__hx_function_value");
	final arguments = names.internalName("__hx_function_arguments");
	final count = names.internalName("__hx_function_count");
	final bindings = new Array<String>();
	final converted = new Array<String>();
	for (index in 0...parameters.length) {
		final raw = names.internalName("__hx_function_input_" + index);
		final type = TyAliasExpansion.reveal(parameters[index].type);
		bindings.push("let "
			+ raw
			+ " = if "
			+ count
			+ " > "
			+ index
			+ " then HxArray.get "
			+ arguments
			+ " "
			+ index
			+ " else HxRuntime.hx_null in ");
		final missing = missingValue(type);
		final read = input(type, raw, names);
		converted.push("(" + (missing == null ? read : "if " + count + " > " + index + " then " + read + " else " + missing) + ")");
	}
	final call = closure + (converted.length == 0 ? " ()" : " " + converted.join(" "));
	return "(let "
		+ closure
		+ " = ("
		+ value
		+ ") in HxReflect.makeVarArgs (Obj.repr (fun ("
		+ arguments
		+ " : Obj.t HxArray.t) -> let "
		+ count
		+ " = HxArray.length "
		+ arguments
		+ " in if "
		+ count
		+ " > "
		+ parameters.length
		+ " then HxRuntime.hx_throw_typed (Obj.repr \"Invalid number of arguments\") [\"String\"; \"Dynamic\"] else "
		+ bindings.join("")
		+ result(actual.getFunctionReturn(), call)
		+ ")))";
}

/** The value of a missing argument for a parameter that cannot hold null, or null when null itself is passed. */
function missingValue(type:TyType):Null<String> {
	if (type.isNullable() || type.isDynamic())
		return null;
	return switch type.getSemanticKey() {
		case "primitive:Int": "0";
		case "primitive:Float": "0.";
		case "primitive:Bool": "false";
		case _: null;
	};
}

/** Convert one `Obj.t` input into the carrier of a parameter of `type`. */
function input(type:TyType, value:String, names:Stage3OcamlLocalNames):String {
	if (type.isDynamic())
		return value;
	if (Stage3OcamlNullablePrimitive.innerPrimitive(type) != null)
		return Stage3OcamlValueConversion.convert(TyType.fromHintText("Dynamic"), type, value, names);
	return switch type.getSemanticKey() {
		case "primitive:String":
			"(if HxRuntime.is_null "
			+ value
			+ " then (Obj.magic HxRuntime.hx_null : string) else HxDynamic.toStdString "
			+ value
			+ ")";
		case "primitive:Float":
			"(if Obj.is_int "
			+ value
			+ " && not (HxRuntime.is_null "
			+ value
			+ ") then float_of_int (Obj.obj "
			+ value
			+ " : int) else if not (Obj.is_int "
			+ value
			+ ") && Obj.tag "
			+ value
			+ " = Obj.double_tag then (Obj.obj "
			+ value
			+ " : float) else HxRuntime.hx_throw_typed (Obj.repr \"Invalid Dynamic value; expected Float\") [\"String\"; \"Dynamic\"])";
		case "primitive:Int" | "primitive:Bool":
			Stage3OcamlValueConversion.convert(TyType.fromHintText("Dynamic"), type, value, names);
		case _:
			"Obj.obj " + value;
	};
}

/** Box a result for the Dynamic convention. */
function result(type:TyType, call:String):String {
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
