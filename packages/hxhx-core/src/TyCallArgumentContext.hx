/**
	Find callback, collection, enum or enum-abstract context shared by admitted callable
	parameters. An enum-abstract parameter lets a bare value such as `Fast` resolve through
	its expected type before candidate scoring, as an enum parameter does.
	Collection context reaches empty literals inside branches before inference seals
	them as Array<Dynamic>. Existing declared values keep their own types.
	Only arguments with an unambiguous source position get a context before operand
	typing: every argument of a fully supplied fixed list, and otherwise each argument
	whose parameter and all earlier parameters are required. `t.start(() -> trace(1), 1000)`
	for `start(callback:() -> Void, ms:Int, ?repeat:Int)` gives the callback its context,
	as upstream Haxe 4.3.7 does. Rest and optional-argument skipping keep their own owner.
 */
function shared(signatures:Array<TyFunSig>, arity:Int, ?methodParameters:Array<Array<TyTypeParameterId>>, ?declarationIndex:TyperIndex):Array<Null<TyType>> {
	if (methodParameters != null && methodParameters.length != signatures.length)
		throw "call context requires method binders for each signature";
	// Only method-owned binders are inference holes. Receiver and caller binders
	// retain their exact identities; a generic result must not become a rigid
	// annotation on the callback body before that body supplies result evidence.
	final arguments = [
		for (index in 0...signatures.length) {
			final bindings = new haxe.ds.StringMap<TyType>();
			if (methodParameters != null) for (parameter in methodParameters[index])
				bindings.set(parameter.getCanonicalKey(), TyType.unknown());
			[
				for (type in signatures[index].getArgs())
					TyTypeSubstitution.apply(type, bindings)
			];
		}
	];
	var positional = arity;
	for (signature in signatures) {
		final count = positionalArguments(signature, arity);
		if (count < positional)
			positional = count;
	}
	if (positional == 0)
		return [for (_ in 0...arity) null];
	final contexts = agreed([for (types in arguments) types.slice(0, positional)], positional, declarationIndex);
	return [for (index in 0...arity) index < positional ? contexts[index] : null];
}

/**
	The number of leading arguments that must fill the parameter at their own index.
	A fully supplied fixed list places all of them. Omitted arguments must all be optional,
	and an optional parameter can be skipped, so placement stops at the first optional one.
**/
private function positionalArguments(signature:TyFunSig, arity:Int):Int {
	final parameters = signature.getArgs();
	final optional = signature.getArgOptional();
	if (signature.getArgRest().indexOf(true) >= 0 || parameters.length < arity)
		return 0;
	if (parameters.length == arity)
		return arity;
	// An omitted required parameter makes the call invalid: it gets no early context.
	for (index in arity...parameters.length)
		if (optional[index] != true)
			return 0;
	var count = 0;
	while (count < arity && optional[count] != true)
		count++;
	return count;
}

/** A known function value supplies its existing parameter row; omission and rest selection stay with call alignment. */
function functionValue(signature:TyCallableSignature, arity:Int, declarationIndex:TyperIndex):Array<Null<TyType>> {
	final parameters = signature.getParameters();
	if (parameters.length != arity || parameters.filter(parameter -> parameter.isRest).length > 0)
		return [for (_ in 0...arity) null];
	return agreed([parameters.map(parameter -> parameter.type)], arity, declarationIndex);
}

/** Share the same admission and equality rules after each callable owner supplies its own binder view. */
private function agreed(arguments:Array<Array<TyType>>, arity:Int, declarationIndex:TyperIndex):Array<Null<TyType>> {
	final contexts:Array<Null<TyType>> = [for (_ in 0...arity) null];
	if (arguments.length == 0)
		return contexts;
	for (index in 0...arity) {
		final first = arguments[0][index];
		final expected = first.isFunction()
			&& first.getFunctionReturn().hasUnknownComponent() ? first.withFunctionTypes(first.getFunctionArguments(), TyType.unknown()) : first;
		if (expected.isFunction()) {
			if (expected.getFunctionArguments().filter(type -> type.hasUnknownComponent()).length > 0)
				continue;
		} else if (TypedCollectionExpectation.context(expected) == null
			&& (expected.hasUnknownComponent()
				|| (TyperContext.expectedEnumOwner(declarationIndex, expected) == null
					&& TyperContext.expectedEnumAbstract(declarationIndex, expected) == null))) {
			continue;
		}
		var agreed = true;
		for (types in arguments) {
			final candidate = types[index];
			final comparable = candidate.isFunction()
				&& candidate.getFunctionReturn()
					.hasUnknownComponent() ? candidate.withFunctionTypes(candidate.getFunctionArguments(), TyType.unknown()) : candidate;
			if (comparable.getSemanticKey() != expected.getSemanticKey())
				agreed = false;
		}
		if (agreed)
			contexts[index] = expected;
	}
	return contexts;
}
