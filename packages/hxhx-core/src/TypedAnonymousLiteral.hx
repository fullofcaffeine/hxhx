/** Context supplies storage types for fresh fields without changing their child expressions. */
function isLiteral(expression:HxExpr):Bool {
	return switch expression {
		case EAnon(_, _): true;
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isLiteral(inner);
		case _: false;
	};
}

/** Match by authored name, since structural type fields use a canonical sorted order. */
function fieldTypes(names:Array<String>, expected:Null<TyType>):Array<TyType> {
	final type = expected == null ? null : expected.unwrapNull();
	final fields = type == null || !type.isAnonymous() ? [] : type.getAnonymousFieldNames();
	final types = type == null || !type.isAnonymous() ? [] : type.getAnonymousFieldTypes();
	return [
		for (name in names) {
			final index = fields.indexOf(name);
			index < 0 ? TyType.unknown() : types[index];
		}
	];
}

/**
	Check each written field against its destination before selecting storage.
	Only present fields enter the literal type: an omitted optional field must
	remain absent. Child inference receives context for nested literals, while
	ordinary child expressions keep their own source types for later conversion.
 */
function infer(input:{
	names:Array<String>,
	values:Array<HxExpr>,
	expected:Null<TyType>,
	typeExpression:(HxExpr, Null<TyType>) -> TyType,
	accepts:(TyType, TyType) -> Bool,
	filePath:String,
	position:HxPos
}):TyType {
	if (input.names.length != input.values.length)
		throw "anonymous literal names do not cover its values";
	final context = input.expected == null ? null : input.expected.unwrapNull();
	final fields = context == null || !context.isAnonymous() ? [] : context.getAnonymousFields();
	final contexts = fieldTypes(input.names, context);
	final types = new Array<TyType>();
	for (index in 0...input.names.length) {
		final name = input.names[index];
		if (input.names.indexOf(name) != index)
			throw new TyperError(input.filePath, input.position, "duplicate object literal field " + name);
		if (fields.length > 0 && context.getAnonymousFieldNames().indexOf(name) < 0)
			throw new TyperError(input.filePath, input.position, "unexpected object literal field " + name);
		final expected = contexts[index].isUnknown() ? null : contexts[index];
		final actual = input.typeExpression(input.values[index], expected);
		if (expected != null && !expected.hasUnknownComponent() && !actual.hasUnknownComponent() && !input.accepts(expected, actual))
			throw new TyperError(input.filePath, input.position,
				"object literal field "
				+ name
				+ ": "
				+ actual.getDisplay()
				+ " is not compatible with "
				+ expected.getDisplay());
		types.push(expected == null || expected.hasUnknownComponent() ? actual : expected);
	}
	for (field in fields)
		if (!field.isOptional && input.names.indexOf(field.name) < 0)
			throw new TyperError(input.filePath, input.position, "missing object literal field " + field.name);
	return TyType.anonymous(input.names, types);
}
