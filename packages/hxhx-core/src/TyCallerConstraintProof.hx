/**
	Prove a forwarded parameter satisfies a callee's bound without replacing that parameter.
	Each caller bound is a guaranteed supertype of the supplied parameter. A matching
	bound proves compatibility; cycles alone prove nothing. Concrete types retain the
	existing constraint rules supplied by the shared typer.
 */
function accepts(expected:TyType, supplied:TyType, bounds:TyTypeParameterId->Null<Array<TyType>>, concrete:(TyType, TyType) -> Bool):Bool {
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
		final declared = bounds(parameter);
		if (declared == null)
			return false;
		for (bound in declared)
			if (visit(bound, seen.concat([key])))
				return true;
		return false;
	}
	return visit(supplied, []);
}
