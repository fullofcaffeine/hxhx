package backend.js;

/**
	A saved Sys.println value uses the same host function as a direct call.
	Shared control lowering can save the callee before evaluating an argument.
	Keep that ordering: resolve the original typed occurrence here instead of
	removing the temporary or interpreting any user member named println as Sys.
**/
function emitValue(expression:HxExpr, scope:JsEmitScope):Null<String> {
	if (scope == null || scope.callableExpressions == null)
		return null;
	switch expression {
		case EField(_, "println"):
		case _:
			return null;
	}
	final source = scope.callableExpressions(expression);
	if (source == null || source.getTag() != FieldRead)
		return null;
	final receivers = source.getExpressions();
	// Only a type qualifier has no receiver effects to preserve. A class object
	// obtained through a local or call keeps its ordinary property evaluation.
	if (receivers.length != 1 || receivers[0].getTag() != RuntimeTypeValue)
		return null;
	final declaration = source.getDeclaration();
	if (declaration == null
		|| !declaration.getIsStatic()
		|| declaration.getOwner().getCanonicalName() != "Sys"
		|| declaration.getModulePath() != "Sys"
		|| declaration.getHasBody()
		|| declaration.getIsDynamic()
		|| declaration.getSignature().getName() != "println")
		return null;
	final signature = declaration.getSignature();
	final arguments = signature.getArgs();
	if (arguments.length != 1
		|| arguments[0].getSemanticKey() != "dynamic"
		|| signature.getReturnType().getSemanticKey() != "primitive:Void")
		throw "JavaScript Sys.println callable has an unsupported provider signature";
	return "console.log";
}
