/**
	Choose storage for an authored try expression from its completing branches.

	A Dynamic branch can flow into a concrete branch's type. Keep that concrete
	type and record its conversion in the typed tree, before target generation.
	An abrupt branch contributes no value; two Dynamic branches stay Dynamic.
 */
function select(current:TyType, handler:TyType):TyType {
	if (!current.isNoNormalCompletion() && !handler.isNoNormalCompletion()) {
		if (current.isDynamic() && !handler.isUnknown())
			return handler;
		if (handler.isDynamic() && !current.isUnknown())
			return current;
	}
	final joined = TyType.unify(current, handler);
	return joined == null ? TyType.fromHintText("Dynamic") : joined;
}

/** Preserve the selected operand once, adding only the required concrete result conversion. */
function convertBranch(value:TypedExpr, result:TyType):TypedExpr {
	if (!value.getType().isDynamic()
		|| result.isUnknown()
		|| result.isDynamic()
		|| result.isNoNormalCompletion()
		|| result.isVoid())
		return value;
	return TypedExpr.castValue(value, result.getCanonicalDisplay(), result, value.getPosition());
}
