/**
	Find callback context that every admitted method signature agrees upon.
	Only fixed, fully supplied parameter lists have an unambiguous source position
	before operand typing. Rest and omitted-argument selection keep their own owner.
 */
function shared(signatures:Array<TyFunSig>, arity:Int, ?methodParameters:Array<Array<TyTypeParameterId>>):Array<Null<TyType>> {
	if (methodParameters != null && methodParameters.length != signatures.length)
		throw "callback context requires method binders for each signature";
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
	final contexts:Array<Null<TyType>> = [for (_ in 0...arity) null];
	if (signatures.length == 0)
		return contexts;
	for (signature in signatures)
		if (signature.getArgs().length != arity || signature.getArgRest().indexOf(true) >= 0)
			return contexts;
	for (index in 0...arity) {
		final first = arguments[0][index];
		final expected = first.isFunction()
			&& first.getFunctionReturn().hasUnknownComponent() ? first.withFunctionTypes(first.getFunctionArguments(), TyType.unknown()) : first;
		if (!expected.isFunction() || expected.getFunctionArguments().filter(type -> type.hasUnknownComponent()).length > 0)
			continue;
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
