/**
	Check writes using the field type already selected for this receiver.
	Instance substitutions and inferred initializer types belong to expression
	typing. This boundary reuses directional assignment and structural proofs;
	it neither widens the field nor mutates the caller's inference state.
 */
function check(input:{
	declaration:TyFieldInfo,
	expected:TyType,
	actual:TyType,
	expression:HxExpr,
	index:TyperIndex,
	filePath:String,
	position:HxPos,
	unchecked:Bool
}):Void {
	if (input.declaration == null || input.unchecked || explicitlyUntyped(input.expression))
		return;
	// Incomplete declarations remain unresolved; they must not become concrete
	// merely because a write supplies a convenient value.
	if (input.expected.hasUnknownComponent() || input.actual.hasUnknownComponent())
		return;
	if (accepts(input.index, input.expected, input.actual, input.expression))
		return;
	throw new TyperError(input.filePath, input.position,
		"assigned type "
		+ input.actual.getDisplay()
		+ " is not compatible with field "
		+ input.declaration.getCanonicalKey()
		+ ":"
		+ input.expected.getDisplay());
}

/** The untyped permission belongs to the whole value, not to an arbitrary nested operand. */
function explicitlyUntyped(expression:HxExpr):Bool {
	return switch expression {
		case EUntyped(_): true;
		case EParenthesized(inner, _): explicitlyUntyped(inner);
		case _: false;
	};
}

private function accepts(index:TyperIndex, expected:TyType, actual:TyType, expression:HxExpr):Bool {
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
	final proof = new TyInferenceSolver("field-assignment");
	return TyStructuralConstraint.constrain(index, proof, TyInferenceSolver.fromType(actual), expected);
}
