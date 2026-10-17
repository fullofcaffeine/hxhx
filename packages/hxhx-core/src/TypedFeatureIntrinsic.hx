/**
	Recognize feature intrinsics only within an authored untyped expression.
	Resolved local and member calls keep their declaration identity. The returned
	structural tree retains every branch for later program-wide feature discovery;
	this pass never decides reachability or evaluates an operand.
 */
function capture(expression:TypedExpr):TypedExpr {
	if (expression.getTag() == MacroExpr || expression.getTag() == MacroType)
		return expression;
	final children = expression.getExpressions();
	final captured = [for (child in children) capture(child)];
	var changed = false;
	for (index in 0...children.length)
		if (children[index] != captured[index])
			changed = true;
	final result = changed ? expression.withExpressions(captured) : expression;
	if (result.getTag() != Call || result.getDeclaration() != null || captured.length == 0)
		return result;
	final callee = captured[0];
	if (callee.getTag() != NameRead || callee.getFieldInfo() != null || callee.getLocalBindings().length != 0)
		return result;
	final names = callee.getTexts();
	if (names.length != 1 || (names[0] != "__feature__" && names[0] != "__define_feature__"))
		return result;
	final definition = names[0] == "__define_feature__";
	if ((definition && captured.length != 3) || (!definition && captured.length != 3 && captured.length != 4))
		throw "feature intrinsic has invalid argument count";
	final name = captured[1];
	if (name.getTag() != StringValue || name.getTexts().length != 1)
		throw "feature intrinsic requires a literal string name";
	return definition ? TypedExpr.featureDefinition(name.getTexts()[0], captured[2],
		result.getPosition()) : TypedExpr.featureSelection(name.getTexts()[0], captured[2], captured.length == 4 ? captured[3] : null, result.getPosition());
}
