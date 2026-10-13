/**
	Identify the bare, nonempty trace syntax owned by the language. With no-traces,
	its operands are not typed or evaluated, even when a local has the same name.
	Qualified calls, parenthesized callees, and empty calls remain ordinary calls.
	Enabled logging keeps a language operation, not a callable declaration.
 */
function isLanguageCall(expression:HxExpr):Bool {
	return switch expression {
		case ECall(EIdent("trace"), arguments): arguments.length > 0;
		case _: false;
	};
}

/** Apply request policy before typing any operands of the language operation. */
function isDisabled(expression:HxExpr, disabled:Bool):Bool
	return disabled && isLanguageCall(expression);
