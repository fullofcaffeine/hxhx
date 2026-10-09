/** Replace completing arrow yields with insertions while preserving loop and branch ownership. */
function insertYields(expression:TypedExpr, map:TypedExpr):TypedExpr {
	final children = expression.getExpressions();
	return switch expression.getTag() {
		case SourceFor:
			expression.withExpressions([children[0], insertYields(children[1], map)]);
		case SourceIf:
			expression.withExpressions([children[0]].concat([for (index in 1...children.length) insertYields(children[index], map)]));
		case Parenthesized:
			insertYields(children[0], map);
		case Binary if (expression.getTexts()[0] == "=>" && children.length == 2):
			TypedExpr.mapInsert(map, children[0], children[1], expression.getPosition());
		case _:
			throw "map comprehension requires a typed arrow yield";
	};
}
