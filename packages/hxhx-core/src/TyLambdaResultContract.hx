/**
 * Checks one normally completing result against a function's written return type.
 * The typer calls this before joining branch types, so a Void branch cannot be
 * hidden by a value-producing branch. Throwing paths impose no result obligation.
 */
function check(actual:TyType, expected:Null<TyType>, filePath:String, position:HxPos, strict:Bool):Void {
	if (expected == null || actual.isNoNormalCompletion())
		return;
	if (actual.isVoid() && !expected.isVoid())
		throw new TyperError(filePath, position, "Missing return: " + expected.getDisplay());
	if (strict && ((expected.isVoid() && !actual.isVoid() && !actual.isUnknown()) || TyType.unify(expected, actual) == null))
		throw new TyperError(filePath, position, "lambda result " + actual.getDisplay() + " is not compatible with " + expected.getDisplay());
}
