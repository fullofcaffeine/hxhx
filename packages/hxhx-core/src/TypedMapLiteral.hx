/**
	Exact indexed collection arguments supply context; short names cannot identify a Map.
	An overload candidate's unbound method parameters need argument inference first.
	Caller-owned generic parameters remain valid context in a generic method body.
 */
function context(expected:Null<TyType>, ?unbound:Array<TyTypeParameterId>):Null<{type:TyType, key:TyType, value:TyType}> {
	if (expected == null)
		return null;
	final type = expected.unwrapNull();
	final identity = type.getNominalIdentity();
	final arguments = type.getTypeArguments();
	if (unbound != null)
		for (identity in TyTypeSubstitution.parameterIdentities(type))
			for (parameter in unbound)
				if (parameter.equals(identity))
					return null;
	return identity != null
		&& identity.getCanonicalName() == "haxe.ds.Map"
		&& arguments.length == 2
		&& !type.hasUnknownComponent() ? {type: type, key: arguments[0], value: arguments[1]} : null;
}

/** Only authored arrow literals receive fresh-literal context during overload trials. */
function isLiteral(expression:HxExpr):Bool {
	return switch expression {
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isLiteral(inner);
		case EArrayDecl(values): values.length > 0 && values[0].match(EBinop("=>", _, _));
		case _: false;
	};
}

/**
	Infer an arrow literal's key and value types before target representation.

	An ordinary array returns null without typing its children. A Map types each
	key before its value, in source order, and retains the real provider identity.
	Missing providers remain unresolved; a backend cannot replace that evidence
	with a guessed class name or native storage type.
 */
function infer(input:{
	values:Array<HxExpr>,
	expected:Null<TyType>,
	typeExpression:(HxExpr, Null<TyType>) -> TyType,
	accepts:(TyType, TyType) -> Bool,
	resolveProvider:Void->Null<TyNominalInfo>,
	filePath:String,
	position:HxPos
}):Null<TyType> {
	var hasArrow = false;
	for (value in input.values)
		if (value.match(EBinop("=>", _, _)))
			hasArrow = true;
	if (!hasArrow)
		return null;
	final selected = context(input.expected);
	var keyType:Null<TyType> = null;
	var valueType:Null<TyType> = null;
	for (entry in input.values)
		switch entry {
			case EBinop("=>", key, value):
				final keyResult = input.typeExpression(key, selected == null ? null : selected.key);
				final valueResult = input.typeExpression(value, selected == null ? null : selected.value);
				if (selected != null) {
					if (!input.accepts(selected.key, keyResult) || !input.accepts(selected.value, valueResult))
						throw new TyperError(input.filePath, input.position, "Map literal entry is not compatible with its declared key and value types");
					continue;
				}
				keyType = keyType == null ? keyResult : TyType.unify(keyType, keyResult);
				valueType = valueType == null ? valueResult : TyType.unify(valueType, valueResult);
				if (keyType == null || valueType == null)
					throw new TyperError(input.filePath, input.position, "Map literal entries require compatible key and value types");
			case _:
				throw new TyperError(input.filePath, input.position, "Map literal entries must all contain a key and value");
		}
	if (selected != null)
		return selected.type;
	final provider = input.resolveProvider();
	final arguments = [keyType, valueType];
	return provider != null
		&& provider.getIdentity()
			.getCanonicalName() == "haxe.ds.Map" ? TyType.nominal(provider.getIdentity(), arguments) : TyType.unresolved("haxe.ds.Map", arguments);
}
