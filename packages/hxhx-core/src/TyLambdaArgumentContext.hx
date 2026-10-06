/**
	Find callback context that every admitted method signature agrees upon.
	Only fixed, fully supplied parameter lists have an unambiguous source position
	before operand typing. Rest and omitted-argument selection keep their own owner.
 */
function shared(signatures:Array<TyFunSig>, arity:Int):Array<Null<TyType>> {
	final contexts:Array<Null<TyType>> = [for (_ in 0...arity) null];
	if (signatures.length == 0)
		return contexts;
	for (signature in signatures)
		if (signature.getArgs().length != arity || signature.getArgRest().indexOf(true) >= 0)
			return contexts;
	for (index in 0...arity) {
		final expected = signatures[0].getArgs()[index];
		if (!expected.isFunction() || expected.hasUnknownComponent())
			continue;
		var agreed = true;
		for (signature in signatures)
			if (signature.getArgs()[index].getSemanticKey() != expected.getSemanticKey())
				agreed = false;
		if (agreed)
			contexts[index] = expected;
	}
	return contexts;
}
