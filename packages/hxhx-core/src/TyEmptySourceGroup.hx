/**
	An empty brace group becomes an object value when an expression needs a value.
	A function body with the same syntax still falls through without returning.
	Keep this distinction in typing so parsing and macro quotations retain EBlock([]).
 */
function isEmpty(expression:HxExpr):Bool {
	return switch expression {
		case ESourceGroup(children, _): children.length == 0;
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isEmpty(inner);
		case _: false;
	};
}

/** Preserve the original wrapper syntax while marking an empty function body as Void. */
function functionBody(expression:TypedExpr):TypedExpr {
	return switch expression.getTag() {
		case SourceGroup if (expression.getExpressions().length == 0): expression.withType(TyType.fromHintText("Void"));
		case Parenthesized | PrivateAccess:
			final child = functionBody(expression.getExpressions()[0]);
			expression.withExpressions([child]).withType(child.getType());
		case _: expression;
	};
}
