package backend.ocaml;

/**
	Store a typed function where `haxe.Constraints.Function` is expected.

	A `Function` value is called through the Dynamic convention:
	`Reflect.callMethod(o, f, args)` hands it the `Obj.t` elements of `args`,
	whatever their number and runtime category. A typed closure cannot receive
	those directly. A listener such as `function(d) Sys.println("listener " +
	d)` is typed `String -> Void` (upstream infers String for `d` too), and an
	Int arriving in its `string` slot crashed the native program.

	The adapter wraps the closure with `HxReflect.functionValue`. The wrapper is
	a real OCaml closure of the function's arity, so a direct call through a
	Dynamic value works. `HxReflect.callMethod` recognizes it and hands it the
	whole argument array, which gives these rules:
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

	Destinations are deny-by-default. Only call arguments, `Function` and
	`Null<Function>` locals and `Array<Function>` literal elements are adapted.
	`requireAdapted` stops emission with a named error for every other place
	typing let a function value enter a `Function` slot.
**/
/** The most parameters `HxReflect.functionValue` and `HxReflect.callMethod` support. */
inline final MAX_ARITY = 5;

function adapt(actual:TyType, value:String, names:Null<Stage3OcamlLocalNames>):Null<String> {
	if (!TyFunctionConstraint.isFunctionValue(actual))
		return null;
	final functionType = actual.unwrapNull();
	if (names == null || functionType.hasUnknownComponent())
		throw "stage3 emitter: a function with an incomplete type cannot be stored as haxe.Constraints.Function yet";
	final parameters = functionType.getFunctionParameters();
	for (parameter in parameters)
		if (parameter.isOptional || parameter.isRest)
			throw "stage3 emitter: a function with optional or rest parameters cannot be stored as haxe.Constraints.Function yet";
	if (parameters.length > MAX_ARITY)
		throw "stage3 emitter: a function with more than " + MAX_ARITY + " parameters cannot be stored as haxe.Constraints.Function yet";
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
	final wrapper = "HxReflect.functionValue "
		+ parameters.length
		+ " (fun ("
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
		+ result(functionType.getFunctionReturn(), call)
		+ ")";
	// A nullable function value stays null instead of being wrapped.
	final guarded = actual.isNullable() ? "if HxRuntime.is_null (Obj.repr " + closure + ") then HxRuntime.hx_null else " + wrapper : wrapper;
	return "(let " + closure + " = (" + value + ") in " + guarded + ")";
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

/**
	Refuse every `Function` destination that was not adapted.

	This is deny-by-default on purpose. Typing accepts a function value at every
	`haxe.Constraints.Function` destination, but only call arguments, plain
	`Function` locals and `Array<Function>` literal elements are adapted. Any
	other destination would hold a raw typed closure, which crashes when
	`Reflect.callMethod` hands it arguments of another category or count.
**/
function requireAdapted(flows:Array<TypedBackendFunctionConstraintFlow>, arguments:Array<TypedBackendCallArgument>, adapted:Array<HxExpr>, file:Null<String>,
		?writes:Array<TypedBackendLocalWrite>):Void {
	function at(position:Null<HxPos>):String
		return (file == null ? "" : file + ":") + (position == null ? "" : position.getLine() + ": ");
	for (flow in flows)
		throw "stage3 emitter: "
			+ at(flow.position)
			+ "a function value cannot be stored as haxe.Constraints.Function in this "
			+ flow.site
			+ " on the native OCaml route yet (haxe_ocaml-h9dw9)";
	for (argument in arguments)
		if (!Lambda.exists(adapted, claimed -> claimed == argument.expression))
			throw "stage3 emitter: "
				+ at(null)
				+ "a function value cannot be passed as haxe.Constraints.Function to this call on the native OCaml route yet (haxe_ocaml-h9dw9)";
	// A generated result local (a lowered conditional, for example) can receive
	// a function value without going through the local storage adapter.
	if (writes != null)
		for (write in writes)
			if (!Lambda.exists(adapted, claimed -> claimed == write.expression))
				throw "stage3 emitter: "
					+ at(null)
					+ "a function value cannot be stored as haxe.Constraints.Function in this local value on the native OCaml route yet (haxe_ocaml-h9dw9)";
}

/**
	Call a value read from a Dynamic field or structure through
	`HxReflect.callMethod`, which checks a `Function` wrapper's argument count
	and rejects a value that is not a function. The callee and each argument are
	evaluated once, in Haxe's left-to-right order.
**/
function dynamicCall(callee:String, arguments:Array<String>, names:Stage3OcamlLocalNames):String {
	final closure = names.internalName("__hx_dynamic_callee");
	final bound = [
		for (index in 0...arguments.length)
			names.internalName("__hx_dynamic_argument_" + index)
	];
	var body = "HxReflect.callMethod HxRuntime.hx_null "
		+ closure
		+ " (HxBootArray.of_list ["
		+ [for (name in bound) "Obj.repr " + name].join("; ") + "])";
	var index = bound.length;
	while (index-- > 0)
		body = "let " + bound[index] + " = (" + arguments[index] + ") in " + body;
	return "(Obj.magic (let " + closure + " = (Obj.repr (" + callee + ")) in " + body + "))";
}
