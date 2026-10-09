/**
	Identify the bare, nonempty trace syntax owned by the language. With no-traces,
	its operands are not typed or evaluated, even when a local has the same name.
	Qualified calls, parenthesized callees, and empty calls remain ordinary calls.
	This policy does not invent a callable declaration for enabled logging.
 */
function isDisabled(expression:HxExpr, disabled:Bool):Bool {
	return disabled && switch expression {
		case ECall(EIdent("trace"), arguments): arguments.length > 0;
		case _: false;
	};
}
