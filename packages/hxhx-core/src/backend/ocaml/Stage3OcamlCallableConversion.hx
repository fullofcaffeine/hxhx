package backend.ocaml;

import backend.ocaml.Stage3OcamlValueConversion.convert;

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
	return returnValue(facts.bodyType, expected, value, names);
}

/** Both expression bodies and exact block returns use the same checked conversion. */
function returnValue(actual:TyType, expected:TyType, value:String, names:Stage3OcamlLocalNames):String {
	if (actual.getSemanticKey() == expected.getSemanticKey())
		return value;
	if (expected.isVoid())
		return "ignore (" + value + ")";
	validateReturn(actual, expected);
	return convert(actual, expected, value, names);
}

/** Reject unsupported carriers before the native statement adapter admits a function. */
function validateReturn(actual:TyType, expected:TyType):Void {
	if (actual.hasUnknownComponent() || expected.hasUnknownComponent())
		throw "OCaml lambda return conversion requires complete types";
	if (actual.getSemanticKey() == expected.getSemanticKey() || expected.isVoid())
		return;
	if (TyAssignmentCompatibility.classify(expected, actual, Unchecked) != Compatible)
		throw "OCaml lambda body does not satisfy its return contract";
	final scalar = actual.isDynamic() ? expected : actual;
	if (!(actual.isDynamic() || expected.isDynamic())
		|| !["primitive:Bool", "primitive:Int", "primitive:String"].contains(scalar.getSemanticKey()))
		throw "unsupported OCaml block return representation conversion";
}
