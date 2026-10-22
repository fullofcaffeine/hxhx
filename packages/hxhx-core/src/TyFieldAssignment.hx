/**
	Check writes using the field type already selected for this receiver.
	Instance substitutions and inferred initializer types belong to expression
	typing. This boundary reuses directional assignment and structural proofs;
	it neither widens the field nor mutates the caller's inference state.
	The caller supplies a diagnostic name only after resolving declared storage
	or an extern dynamic-member contract. An absent name means neither applies.
 */
function check(input:{
	fieldName:Null<String>,
	expected:TyType,
	actual:TyType,
	expression:HxExpr,
	index:TyperIndex,
	filePath:String,
	position:HxPos,
	unchecked:Bool
}):Void {
	if (input.fieldName == null || input.unchecked || explicitlyUntyped(input.expression))
		return;
	// Incomplete declarations remain unresolved; they must not become concrete
	// merely because a write supplies a convenient value.
	if (input.expected.hasUnknownComponent() || input.actual.hasUnknownComponent())
		return;
	if (TyValueCompatibility.accepts(input.index, input.expected, input.actual, input.expression))
		return;
	throw new TyperError(input.filePath, input.position,
		"assigned type "
		+ input.actual.getDisplay()
		+ " is not compatible with field "
		+ input.fieldName
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
