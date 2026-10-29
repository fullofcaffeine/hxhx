/**
	Join alternative expression values without losing a branch that produces null.
	Ordinary unification also serves assignment compatibility and can accept a
	null literal for a non-null branch type. A conditional needs storage for
	either actual value, so it retains nullable presence in its selected result.
	When unrelated branch identities prevent a join, a declared result can select
	existing abstract conversions for both branches. Dynamic values do not gain a
	conversion from that context. Typed branch construction materializes the selected
	conversions; this function introduces no target operation or numeric rule.
 */
function join(left:TyType, right:TyType, ?expected:TyType, ?index:TyperIndex):Null<TyType> {
	var selected = TyType.unify(left, right);
	if ((selected == null || selected.isDynamic())
		&& expected != null
		&& index != null
		&& !expected.isUnknown()
		&& !expected.isDynamic()
		&& !expected.isVoid()
		&& converts(left, expected, index)
		&& converts(right, expected, index))
		selected = expected;
	if (selected == null || selected.isNullLiteral() || selected.isNullable() || selected.isDynamic() || selected.isVoid() || selected.isNoNormalCompletion())
		return selected;
	return left.isNullLiteral() || right.isNullLiteral() ? TyType.nullable(selected) : selected;
}

/** Equal backing storage is insufficient: an abstract must declare the selected conversion. */
private function converts(source:TyType, target:TyType, index:TyperIndex):Bool {
	if (source.isUnknown() || source.isDynamic() || source.isVoid())
		return false;
	if (source.getSemanticKey() == target.getSemanticKey())
		return true;
	final storage = TyImplicitConversionPlan.select(index, target, source);
	return (storage != null && storage.isRepresentationPreservingAbstractConversion())
		|| TyAbstractMethodConversion.select(index, target, source) != null;
}
