package backend.source;

/**
	Render a function with one value return as a native Python lambda.
	Shared typing supplies the return destination. Validate it before selecting
	the returned expression, preserving its operand objects and lexical captures.
	Python lambdas cannot execute statement bodies, so reject those bodies before
	rendering any value rather than dropping their effects.
 */
function render(arguments:String, body:HxExpr, expression:HxExpr->String):String {
	final statements = TypedControlStatements.functionBody(body);
	return switch statements {
		case [SReturn(value, _)]: "lambda " + arguments + ": " + expression(value);
		case _: throw "Python expression function requires a single value return";
	};
}
