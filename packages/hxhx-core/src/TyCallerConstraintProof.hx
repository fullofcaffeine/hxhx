import haxe.ds.StringMap;

/** Read immutable bounds from the exact enclosing method, never from a same-named binder. */
function boundsForFunction(owner:Null<TyNominalInfo>, identity:String):StringMap<Array<TyType>> {
	if (owner != null)
		for (declaration in owner.getDeclarations())
			if (declaration.getIdentity().getCanonicalKey() == identity)
				return declaration.getResolvedTypeParameterConstraints();
	return new StringMap<Array<TyType>>();
}

/**
	Prove a forwarded parameter satisfies a callee's bound without replacing that parameter.
	Each caller bound is a guaranteed supertype of the supplied parameter. A matching
	bound proves compatibility; cycles alone prove nothing. Concrete types retain the
	existing constraint rules supplied by the shared typer.
 */
function accepts(expected:TyType, supplied:TyType, bounds:StringMap<Array<TyType>>, concrete:(TyType, TyType) -> Bool):Bool {
	function visit(current:TyType, seen:Array<String>):Bool {
		if (current == null || current.hasUnknownComponent() || expected.hasUnknownComponent())
			return false;
		if (expected.getSemanticKey() == current.getSemanticKey())
			return true;
		if (expected.isDynamic())
			return concrete(expected, current);
		if (current.isNullable())
			return visit(current.unwrapNull(), seen);
		final parameter = current.getTypeParameterIdentity();
		if (parameter == null)
			return concrete(expected, current);
		final key = parameter.getCanonicalKey();
		if (seen.indexOf(key) >= 0)
			return false;
		final declared = bounds.get(key);
		if (declared == null)
			return false;
		for (bound in declared)
			if (visit(bound, seen.concat([key])))
				return true;
		return false;
	}
	return visit(supplied, []);
}
