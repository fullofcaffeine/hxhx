/** The caller supplies the null-safety requirement after its flow analysis. */
enum TyAssignmentNullPolicy {
	Unchecked;
	Strict;
}

/**
	Query directional value assignment without mutating inference or choosing an overload.

	Exact resolved types, primitives, function signatures, explicit Dynamic, and the supplied nullable
	policy are supported here. Other relationships remain Unknown until their
	inheritance, structural, generic, or abstract-conversion proof is available.
	An Unknown compatibility result must never seal a call. An explicit Dynamic
	destination can receive a known value with unresolved inner inference types
	because it promises no typed access to those components. Their source types
	remain unchanged. This owner does not emit conversions or perform flow-sensitive null analysis.
 */
function classify(expected:TyType, actual:TyType, nullPolicy:TyAssignmentNullPolicy):TyCallArgumentCompatibility {
	// An explicit Dynamic destination makes no promise about the fields, type
	// arguments, or callable inputs of an already identified value. Preserve
	// those inference variables; unresolved named types are still invalid.
	if (expected != null && expected.isDynamic() && actual != null && !actual.isUnknown() && !incomplete(actual, true))
		return actual.isVoid() ? Incompatible : Compatible;
	if (incomplete(expected) || incomplete(actual))
		return Unknown;
	if (expected.isVoid() || actual.isVoid() || expected.isNoNormalCompletion())
		return Incompatible;
	if (actual.isNoNormalCompletion())
		return Compatible;
	if (expected.isDynamic() || actual.isDynamic())
		return Compatible;
	if (actual.isNullLiteral())
		return nullPolicy == Unchecked || expected.isNullable() || expected.isNullLiteral() ? Compatible : Incompatible;
	if (expected.isNullLiteral())
		return Incompatible;
	if (actual.isNullable() && !expected.isNullable() && nullPolicy == Strict)
		return Incompatible;
	if (expected.isNullable() || actual.isNullable())
		return classify(expected.unwrapNull(), actual.unwrapNull(), nullPolicy);
	if (expected.getSemanticKey() == actual.getSemanticKey())
		return Compatible;
	if (expected.isFunction() && actual.isFunction())
		return functions(expected, actual, nullPolicy);
	if (expected.isPrimitive() && actual.isPrimitive())
		return expected.isNumeric() && actual.isNumeric() && expected.getDisplay() == "Float" ? Compatible : Incompatible;
	return nominalArguments(expected, actual);
}

/**
	Compare arguments of the same resolved nominal constructor without value conversions.
	A written Dynamic argument can receive a known argument, including a caller's
	type parameter. The reverse would promise a concrete type the source does not
	guarantee. Numeric widening is likewise invalid inside invariant containers.
	This proves assignment only; target storage and conversion remain target-owned.
 */
private function nominalArguments(expected:TyType, actual:TyType):TyCallArgumentCompatibility {
	final wanted = expected.getNominalIdentity();
	final supplied = actual.getNominalIdentity();
	if (wanted == null || supplied == null || wanted.getCanonicalName() != supplied.getCanonicalName())
		return Unknown;
	final targets = expected.getTypeArguments();
	final sources = actual.getTypeArguments();
	if (targets.length == 0 || targets.length != sources.length)
		return Unknown;
	var result:TyCallArgumentCompatibility = Compatible;
	for (index in 0...targets.length) {
		final target = targets[index];
		final source = sources[index];
		if (target.isNullable()
			&& (target.unwrapNull().isDynamic() || target.unwrapNull().getSemanticKey() == source.unwrapNull().getSemanticKey()))
			continue;
		if (target.getSemanticKey() == source.getSemanticKey() || target.isDynamic())
			continue;
		if (source.isDynamic() || (target.isPrimitive() && source.isPrimitive()))
			return Incompatible;
		final nested = nominalArguments(target, source);
		if (nested == Incompatible)
			return Incompatible;
		if (nested == Unknown)
			result = Unknown;
	}
	return result;
}

/**
	Check the whole operand of a spread into a rest parameter.

	Haxe 4.3.7 accepts exact Array and Rest element types, or an explicit Dynamic
	container. Array<Int> cannot supply Rest<Float>, and Array<Dynamic> cannot
	supply Rest<Int>. Container identity comes from resolution, never display text.
	Other generic and abstract-container relationships remain unproved.
 */
function classifyRestSpread(expectedElement:TyType, actualContainer:TyType):TyCallArgumentCompatibility {
	if (incomplete(expectedElement) || incomplete(actualContainer))
		return Unknown;
	if (actualContainer.isDynamic())
		return Compatible;
	if (actualContainer.isPrimitive())
		return Incompatible;
	final identity = actualContainer.getNominalIdentity();
	final arguments = actualContainer.getTypeArguments();
	if (identity == null
		|| (identity.getCanonicalName() != "Array" && identity.getCanonicalName() != "haxe.Rest")
		|| arguments.length != 1)
		return Unknown;
	final actualElement = arguments[0];
	if (expectedElement.getSemanticKey() == actualElement.getSemanticKey())
		return Compatible;
	if (expectedElement.isPrimitive() && (actualElement.isPrimitive() || actualElement.isDynamic()))
		return Incompatible;
	return Unknown;
}

/**
	A replacement callback must accept the caller's arguments and provide its expected result.

	Parameters therefore reverse assignment direction; results retain it. A Void
	result permits discarding a returned value. Optional parameters cannot become
	required, and function assignment preserves the declared parameter count.
	Rest containers require separate comparison because their elements cannot widen.
 */
private function functions(expected:TyType, actual:TyType, nullPolicy:TyAssignmentNullPolicy):TyCallArgumentCompatibility {
	final wanted = expected.getFunctionParameters();
	final supplied = actual.getFunctionParameters();
	if (wanted.length != supplied.length)
		return Incompatible;
	var result:TyCallArgumentCompatibility = Compatible;
	for (index in 0...wanted.length) {
		final target = wanted[index];
		final source = supplied[index];
		if (target.isOptional && !source.isOptional)
			return Incompatible;
		final parameter = target.isRest || source.isRest ? restParameter(target, source) : classify(source.type, target.type, nullPolicy);
		if (parameter == Incompatible)
			return Incompatible;
		if (parameter == Unknown)
			result = Unknown;
	}
	final wantedResult = expected.getFunctionReturn();
	final suppliedResult = actual.getFunctionReturn();
	final returned:TyCallArgumentCompatibility = wantedResult.isVoid() ? Compatible : classify(wantedResult, suppliedResult, nullPolicy);
	if (returned == Incompatible)
		return Incompatible;
	return returned == Unknown ? Unknown : result;
}

/**
	Preserve proven Rest element identity and reject primitive container mismatches.
	Other container relationships need resolved generic or abstract-conversion proof.
 */
private function restParameter(expected:TyFunctionParameter, actual:TyFunctionParameter):TyCallArgumentCompatibility {
	if (expected.isRest && actual.isRest) {
		if (expected.type.getSemanticKey() == actual.type.getSemanticKey())
			return Compatible;
		return expected.type.isPrimitive() && actual.type.isPrimitive() ? Incompatible : Unknown;
	}
	final fixedType = expected.isRest ? actual.type : expected.type;
	return fixedType.isPrimitive() ? Incompatible : Unknown;
}

/** Only explicit Dynamic erasure may leave nested inference variables unsolved; named types must always resolve. */
private function incomplete(type:TyType, eraseInference:Bool = false):Bool {
	if (type == null || (!eraseInference && type.isUnknown()) || type.isUnresolved())
		return true;
	if (type.isNullable() && incomplete(type.getNullableInner(), eraseInference))
		return true;
	for (argument in type.getTypeArguments())
		if (incomplete(argument, eraseInference))
			return true;
	if (type.isFunction()) {
		for (argument in type.getFunctionArguments())
			if (incomplete(argument, eraseInference))
				return true;
		if (incomplete(type.getFunctionReturn(), eraseInference))
			return true;
	}
	for (field in type.getAnonymousFieldTypes())
		if (incomplete(field, eraseInference))
			return true;
	return false;
}
