import TypedExpr.TypedExprTag;

/**
	Retain the storage selected by a compound assignment before its right operand.
	The caller captures each address operand once in its exact function scope.
	Unlike a simple field assignment, a compound update must also read the old
	value before the right operand can redirect a receiver or modify that storage.
 */
function retain(destination:TypedExpr, capture:TypedExpr->TypedExpr):TypedExpr {
	final children = destination.getExpressions();
	return switch destination.getTag() {
		case LocalRead if (destination.getLocalBindings().length == 1): destination;
		case NameRead if (destination.getFieldInfo() != null): destination;
		case Parenthesized | Untyped if (children.length == 1):
			destination.withExpressions([retain(children[0], capture)]);
		case FieldRead if (children.length == 1):
			// A static owner denotes storage; it is not a runtime receiver value.
			destination.withExpressions([children[0].getTag() == RuntimeTypeValue ? children[0] : capture(children[0])]);
		case ArrayAccess if (children.length == 2):
			destination.withExpressions([capture(children[0]), capture(children[1])]);
		case _:
			throw "control-valued compound assignment requires a supported exact destination";
	};
}
