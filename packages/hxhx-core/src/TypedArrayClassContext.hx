/**
	Apply an Array class literal to its selected Class<Array<T>> context.
	The exact runtime target already distinguishes a literal from a local, field,
	or same-spelled nominal declaration. The descriptor does not change; a typed
	conversion records the selected context without narrowing stored class values.
 */
function convert(value:TypedExpr, expected:TyType):Null<TypedExpr> {
	if (expected == null || expected.hasUnknownComponent() || value.getType().getSemanticKey() == expected.getSemanticKey())
		return null;
	var literal = value;
	while (literal.getTag() == Parenthesized || literal.getTag() == PrivateAccess) {
		final children = literal.getExpressions();
		if (children.length != 1)
			return null;
		literal = children[0];
	}
	final target = literal.getRuntimeTypeTarget();
	if (literal.getTag() != RuntimeTypeValue
		|| target == null
		|| !target.getKind().match(ArrayCore)
		|| literal.getType().getSemanticKey() != target.getValueType().getSemanticKey())
		return null;
	final context = expected.unwrapNull();
	final identity = context.getNominalIdentity();
	final arguments = context.getTypeArguments();
	if (identity == null || identity.getCanonicalName() != "Class" || arguments.length != 1)
		return null;
	final instance = arguments[0];
	final declaration = instance.getNominalIdentity();
	if (declaration == null || !declaration.equals(target.requireDeclarationIdentity()) || instance.getTypeArguments().length != 1)
		return null;
	return TypedExpr.castValue(value, expected.getDisplay(), expected, value.getPosition(), true);
}
