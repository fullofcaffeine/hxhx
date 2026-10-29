/**
	Prove a written value boundary without changing its source type or caller inference.
	Fields and source annotations share directional assignment, declared conversions,
	caller bounds, and structural compatibility. The caller owns untyped permissions
	and unresolved-input handling; this query does not execute a selected conversion.
 */
function accepts(index:TyperIndex, expected:TyType, actual:TyType, expression:HxExpr):Bool {
	if (!TyStructuralArgument.literalFits(expression, expected))
		return false;
	final basic = TyAssignmentCompatibility.classify(expected, actual, Unchecked);
	if (basic != Unknown)
		return basic == Compatible;
	if (expected.isNullable() || actual.isNullable())
		return accepts(index, expected.unwrapNull(), actual.unwrapNull(), expression);
	if (TyAbstractMethodConversion.select(index, expected, actual) != null)
		return true;
	final conversion = TyImplicitConversionPlan.select(index, expected, actual);
	if (conversion != null && conversion.isRepresentationPreservingAbstractConversion())
		return true;
	if (actual.isTypeParameter() && index != null)
		return TyCallerConstraintProof.accepts(expected, actual, index.getParameterBounds, (target, bound) -> accepts(index, target, bound, expression));
	final proof = new TyInferenceSolver("value-assignment");
	return TyStructuralConstraint.constrain(index, proof, TyInferenceSolver.fromType(actual), expected);
}
