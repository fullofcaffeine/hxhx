/** Preserve a selected array's element contract while checking its literal children. */
function isLiteral(expression:HxExpr):Bool {
	return switch expression {
		case EArrayDecl(_): true;
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isLiteral(inner);
		case _: false;
	};
}

/** Null-only literals contribute nullability while later uses infer the element beneath it. */
function isNullOnly(values:Array<HxExpr>):Bool {
	function isNull(value:HxExpr):Bool {
		return switch value {
			case ENull: true;
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): isNull(inner);
			case _: false;
		};
	}
	return values.length > 0 && values.filter(value -> !isNull(value)).length == 0;
}

/** Only a resolved Array declaration supplies element context to nested literals. */
function elementType(expected:Null<TyType>):Null<TyType> {
	if (expected == null)
		return null;
	final type = expected.unwrapNull();
	final identity = type.getNominalIdentity();
	final arguments = type.getTypeArguments();
	return identity != null
		&& identity.getCanonicalName() == "Array"
		&& arguments.length == 1
		&& !type.hasUnknownComponent() ? arguments[0] : null;
}

/**
	Keep the destination element type, including Dynamic, after checking every
	child. Child expressions retain their own types for storage conversions.
	Arrow literals remain owned by Map inference, not by Array context.
 */
function infer(input:{
	values:Array<HxExpr>,
	expected:Null<TyType>,
	typeExpression:(HxExpr, TyType) -> TyType,
	accepts:(TyType, TyType) -> Bool,
	filePath:String,
	position:HxPos
}):Null<TyType> {
	final element = elementType(input.expected);
	if (element == null)
		return null;
	for (value in input.values) {
		final actual = input.typeExpression(value, element);
		if (!input.accepts(element, actual))
			throw new TyperError(input.filePath, input.position, "array element "
				+ actual.getDisplay()
				+ " is not compatible with "
				+ element.getDisplay());
	}
	return input.expected.unwrapNull();
}
