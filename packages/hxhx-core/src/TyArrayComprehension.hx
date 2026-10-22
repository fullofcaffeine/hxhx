/** A yield selects collection construction by authored syntax, not by its value's type. */
private enum ComprehensionYieldKind {
	ArrayElement;
	MapEntry;
}

/**
	Infer collection elements from yielded values, not the Void result of a loop.
	The authored tree stays intact. Loop and guard scopes follow typed-body replay,
	so names in nested iterables and yields keep their declaration identities.
 */
function infer(input:{
	values:Array<HxExpr>,
	expected:Null<TyType>,
	scope:TyFunctionEnv,
	filePath:String,
	position:HxPos,
	typeExpression:(HxExpr, Null<TyType>) -> TyType,
	typeMapEntry:HxExpr->TyType,
	resolveArray:TyType->TyType
}):Null<TyType> {
	if (input.values.length != 1 || !input.values[0].match(ESourceFor(_, _, _, _)))
		return null;
	final expectedElement = TypedArrayLiteral.elementType(input.expected);
	var yieldKind:Null<ComprehensionYieldKind> = null;
	function select(kind:ComprehensionYieldKind):Void {
		if (yieldKind != null && yieldKind != kind)
			throw new TyperError(input.filePath, input.position, "comprehension cannot mix array elements and map entries");
		yieldKind = kind;
	}
	function yieldedType(expression:HxExpr):TyType {
		return switch expression {
			case ESourceFor(_, _, _, _):
				TySourceFor.infer({
					expression: expression,
					scope: input.scope,
					filePath: input.filePath,
					typeExpression: value -> input.typeExpression(value, null),
					typeBody: yieldedType
				}).bodyType;
			case ESourceIf(condition, yes, no, position):
				input.typeExpression(condition, TyType.fromHintText("Bool"));
				input.scope.enterLexicalScope();
				final yesType = yieldedType(yes);
				input.scope.exitLexicalScope();
				if (no == null) yesType; else {
					input.scope.enterLexicalScope();
					final noType = yieldedType(no);
					input.scope.exitLexicalScope();
					final combined = TyType.unify(yesType, noType);
					if (combined == null)
						throw new TyperError(input.filePath, position, "comprehension branches require compatible yielded values");
					combined;
				}
			case EParenthesized(inner, _): yieldedType(inner);
			case EBinop("=>", _, _):
				select(MapEntry);
				input.typeMapEntry(expression);
			case _:
				select(ArrayElement);
				input.typeExpression(expression, expectedElement);
		};
	}
	final element = yieldedType(input.values[0]);
	return yieldKind == MapEntry ? element : input.resolveArray(expectedElement == null ? element : expectedElement);
}
