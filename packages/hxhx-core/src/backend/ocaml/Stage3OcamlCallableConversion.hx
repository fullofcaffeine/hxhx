package backend.ocaml;

/**
	Adapt a checked Haxe callback assignment across OCaml's concrete/Dynamic ABI.
	The source closure keeps its own parameter types. The wrapper boxes incoming
	values and unwraps its result according to the exact destination callable.
	Dynamic-to-concrete extraction checks the runtime category before Obj.obj.
	These checks protect the native representation; shared assignment checking
	still owns whether the callable types are compatible.
 */
function adapt(argument:TypedBackendCallArgument, value:String, names:Stage3OcamlLocalNames):Null<String> {
	if (argument == null || argument.expectedType == null)
		return null;
	final actual = argument.type;
	final expected = argument.expectedType;
	if (!actual.isFunction() || !expected.isFunction() || actual.getSemanticKey() == expected.getSemanticKey())
		return null;
	if (actual.hasUnknownComponent()
		|| expected.hasUnknownComponent()
		|| TyAssignmentCompatibility.classify(expected, actual, Unchecked) != Compatible)
		throw "OCaml callable conversion requires complete compatible signatures";
	final source = actual.getFunctionParameters();
	final target = expected.getFunctionParameters();
	if (source.length != target.length || names == null)
		throw "OCaml callable conversion requires exact arity and local ownership";
	for (index in 0...source.length)
		if (source[index].isRest || target[index].isRest || source[index].isOptional || target[index].isOptional)
			throw "OCaml callable conversion needs an optional/rest storage plan";
	final closure = names.internalName("__hx_callable");
	// internalName avoids authored locals; each parameter also needs its own base.
	final parameters = [
		for (index in 0...source.length)
			names.internalName("__hx_callback_arg_" + index)
	];
	final arguments = [
		for (index in 0...source.length)
			convert(target[index].type, source[index].type, parameters[index], names)
	];
	final called = closure + (arguments.length == 0 ? " ()" : " " + arguments.map(argument -> "(" + argument + ")").join(" "));
	final returned = expected.getFunctionReturn()
		.isVoid() ? "ignore (" + called + ")" : convert(actual.getFunctionReturn(), expected.getFunctionReturn(), called, names);
	return "(let "
		+ closure
		+ " = ("
		+ value
		+ ") in fun "
		+ (parameters.length == 0 ? "()" : parameters.join(" "))
		+ " -> "
		+ returned
		+ ")";
}

/** Convert an expression body's value at its exact callable return boundary. */
function lambdaResult(facts:TypedBackendLambdaOccurrence, value:String, names:Stage3OcamlLocalNames):String {
	if (facts == null || facts.bodyType.isNoNormalCompletion())
		return value;
	final expected = facts.callableType.getFunctionReturn();
	if (facts.bodyType.getSemanticKey() == expected.getSemanticKey())
		return value;
	if (expected.isVoid())
		return "ignore (" + value + ")";
	if (facts.bodyType.hasUnknownComponent() || expected.hasUnknownComponent())
		throw "OCaml lambda return conversion requires complete types";
	if (TyAssignmentCompatibility.classify(expected, facts.bodyType, Unchecked) != Compatible)
		throw "OCaml lambda body does not satisfy its return contract";
	return convert(facts.bodyType, expected, value, names);
}

/** Boolean boxing stays distinct from the integer carrier; no numeric conversion is introduced. */
private function convert(actual:TyType, expected:TyType, value:String, names:Stage3OcamlLocalNames):String {
	if (actual.getSemanticKey() == expected.getSemanticKey())
		return value;
	final source = actual.getSemanticKey();
	final destination = expected.getSemanticKey();
	if (expected.isDynamic())
		return switch source {
			case "primitive:Bool": "HxRuntime.box_bool (" + value + ")";
			case "primitive:Int" | "primitive:String": "Obj.repr (" + value + ")";
			case _: throw "unsupported OCaml callback input carrier: " + source;
		};
	if (actual.isDynamic())
		return switch destination {
			case "primitive:Bool": "HxDynamic.booleanValue (" + value + ")";
			case "primitive:Int": checkedExtraction(value, "Int", "int", names);
			case "primitive:String": checkedExtraction(value, "String", "string", names);
			case _: throw "unsupported OCaml callback result carrier: " + destination;
		};
	throw "unsupported OCaml callback representation change: " + source + " to " + destination;
}

/** Evaluate once and reject a foreign category before interpreting native bits. */
private function checkedExtraction(value:String, category:String, carrier:String, names:Stage3OcamlLocalNames):String {
	final local = names.internalName("__hx_callback_result");
	final check = category == "Int" ? "Obj.is_int " + local + " && not (HxRuntime.is_null " + local + ")" : "not (Obj.is_int "
		+ local
		+ ") && Obj.tag "
		+ local
		+ " = Obj.string_tag";
	return "(let "
		+ local
		+ " = ("
		+ value
		+ ") in if "
		+ check
		+ " then (Obj.obj "
		+ local
		+ " : "
		+ carrier
		+ ") else HxRuntime.hx_throw_typed (Obj.repr \"Invalid Dynamic callback value; expected "
		+ category
		+ "\") [\"String\"; \"Dynamic\"])";
}
