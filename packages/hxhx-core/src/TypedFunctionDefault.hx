/**
	A named parameter's default, typed in the declaration's own class scope.

	The slot identifies the parameter independently of its projected backend name.
	This expression is conditional entry work, not an ordinary body statement:
	backends must evaluate it only when their checked argument policy selects it.
 */
class TypedFunctionDefault {
	final parameterIndex:Int;
	final expression:TypedExpr;

	public function new(parameterIndex:Int, expression:TypedExpr) {
		if (parameterIndex < 0 || expression == null)
			throw "typed function default requires a parameter slot and expression";
		this.parameterIndex = parameterIndex;
		this.expression = expression;
	}

	public function getParameterIndex():Int
		return parameterIndex;

	public function getExpression():TypedExpr
		return expression;
}

/** Detect edits to mutable parsed arguments before reusing their typed defaults. */
function sourceIdentity(arguments:Array<HxFunctionArg>):String {
	final facts = new Array<Null<String>>();
	for (argument in arguments) {
		facts.push(HxFunctionArg.getName(argument));
		facts.push(HxFunctionArg.getTypeHint(argument));
		facts.push(Std.string(HxFunctionArg.getIsOptional(argument)));
		facts.push(Std.string(HxFunctionArg.getIsRest(argument)));
		facts.push(HxFunctionArg.getDefaultValueText(argument));
		facts.push(CompilerCacheIdentity.encode(HxFunctionArg.getMetadata(argument)));
		facts.push(switch HxFunctionArg.getDefaultValue(argument) {
			case NoDefault: null;
			case Default(expression): TypedBodyFingerprint.exactExpression(expression);
		});
	}
	return CompilerCacheIdentity.encode(facts);
}
