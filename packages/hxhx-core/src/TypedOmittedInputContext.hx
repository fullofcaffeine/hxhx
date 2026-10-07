/**
	Convert a proven unresolved input value for a Dynamic consumer without changing
	its declaration. Sealed inference follows local aliases and field projections;
	an arbitrary Unknown expression or missing compiler fact supplies no such proof.
 */
function convert(source:HxExpr, value:TypedExpr, expected:Null<TyType>, environment:Null<TyFunctionEnv>):TypedExpr {
	if (expected == null || !expected.isDynamic() || !value.getType().isUnknown() || environment == null)
		return value;
	if (!environment.getInference().isUnresolvedInput(source, environment))
		return value;
	return TypedExpr.castValue(value, expected.getDisplay(), expected, value.getPosition());
}
