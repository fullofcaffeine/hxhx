/**
	Infer an arrow literal's key and value types before target representation.

	An ordinary array returns null without typing its children. A Map types each
	key before its value, in source order, and retains the real provider identity.
	Missing providers remain unresolved; a backend cannot replace that evidence
	with a guessed class name or native storage type.
 */
function infer(input:{
	values:Array<HxExpr>,
	typeExpression:HxExpr->TyType,
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
	var keyType:Null<TyType> = null;
	var valueType:Null<TyType> = null;
	for (entry in input.values)
		switch entry {
			case EBinop("=>", key, value):
				final keyResult = input.typeExpression(key);
				final valueResult = input.typeExpression(value);
				keyType = keyType == null ? keyResult : TyType.unify(keyType, keyResult);
				valueType = valueType == null ? valueResult : TyType.unify(valueType, valueResult);
				if (keyType == null || valueType == null)
					throw new TyperError(input.filePath, input.position, "Map literal entries require compatible key and value types");
			case _:
				throw new TyperError(input.filePath, input.position, "Map literal entries must all contain a key and value");
		}
	final provider = input.resolveProvider();
	final arguments = [keyType, valueType];
	return provider != null
		&& provider.getIdentity()
			.getCanonicalName() == "haxe.ds.Map" ? TyType.nominal(provider.getIdentity(), arguments) : TyType.unresolved("haxe.ds.Map", arguments);
}
