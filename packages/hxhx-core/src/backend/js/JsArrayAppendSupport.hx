package backend.js;

/**
	Append a shared-lowering result without reinterpreting source comprehension syntax.
	Typing already selected the array, converted element, and control destinations.
	JavaScript evaluates the receiver and value once in that order. The operation
	remains owned by its original executable even inside a nested callback.
 */
function emit(expression:HxExpr, scope:JsEmitScope):String {
	if (scope == null || scope.requireExpression == null)
		throw "JavaScript array append requires its exact executable projection";
	scope.requireExpression(expression);
	return switch expression {
		case ELoweredControl(ArrayAppend, "", [array, value], _):
			"("
			+ JsExprEmitter.emit(array, scope)
			+ ").push("
			+ JsExprEmitter.emit(value, scope)
			+ ")";
		case _: throw "JavaScript array append has an invalid layout or destination";
	};
}
