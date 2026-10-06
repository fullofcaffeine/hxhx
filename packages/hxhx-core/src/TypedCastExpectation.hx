/** A hint-free cast can receive an overload candidate's destination type without evaluating its operand. */
function isUnchecked(expression:HxExpr):Bool {
	return switch expression {
		case ECast(_, hint): hint.length == 0;
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isUnchecked(inner);
		case _: false;
	};
}
