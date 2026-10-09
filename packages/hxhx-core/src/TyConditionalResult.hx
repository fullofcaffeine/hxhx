/**
	Join alternative expression values without losing a branch that produces null.
	Ordinary unification also serves assignment compatibility and can accept a
	null literal for a non-null branch type. A conditional needs storage for
	either actual value, so it retains nullable presence in its selected result.
	Abrupt completion, Void, unknowns and incompatible joins keep the existing
	shared unification result; this function introduces no target conversion.
 */
function join(left:TyType, right:TyType):Null<TyType> {
	final selected = TyType.unify(left, right);
	if (selected == null || selected.isNullLiteral() || selected.isNullable() || selected.isDynamic() || selected.isVoid() || selected.isNoNormalCompletion())
		return selected;
	return left.isNullLiteral() || right.isNullLiteral() ? TyType.nullable(selected) : selected;
}
