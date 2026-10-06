/**
	Turn each completing yield into an append while retaining authored control facts.
	The shared control lowerer still owns loop entry, scopes, abrupt exits, and
	sequencing. No new function or nested result array is introduced here.
 */
function appendYields(expression:TypedExpr, array:TypedExpr, element:TyType):TypedExpr {
	final children = expression.getExpressions();
	return switch expression.getTag() {
		case SourceFor:
			expression.withExpressions([children[0], appendYields(children[1], array, element)]);
		case SourceIf:
			expression.withExpressions([children[0]].concat([for (index in 1...children.length) appendYields(children[index], array, element)]));
		case _:
			if (!expression.getType().isNoNormalCompletion() && expression.getType().getSemanticKey() != element.getSemanticKey())
				throw "comprehension yield requires its selected element conversion";
			TypedExpr.arrayAppend(array, expression, expression.getPosition());
	};
}
