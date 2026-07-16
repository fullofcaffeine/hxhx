/**
	Validates the primitive carrier operation authorized by a bodyless abstract
	binary declaration.

	A declaration without a Haxe body is the only case where shared lowering may
	use the target-native operator on underlying carriers. This validator keeps
	that decision in semantic typing so compile-time error probes, typed lowering,
	and every backend agree on both the operation result and allowed conversion.
**/
class TyAbstractNativeBinaryOperation {
	public static function carrierType(type:TyType, index:TyperIndex):TyType {
		final identity = type == null ? null : type.getNominalIdentity();
		final info = identity == null || index == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		return info == null ? type : info.getUnderlyingType();
	}

	static function operationType(op:String, left:TyType, right:TyType, declaration:TyDeclarationInfo, filePath:String):TyType {
		if (op == "+" && (left.getDisplay() == "String" || right.getDisplay() == "String"))
			return TyType.fromHintText("String");
		if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && left.isNumeric() && right.isNumeric())
			return left.getDisplay() == "Float"
				|| right.getDisplay() == "Float" ? TyType.fromHintText("Float") : TyType.fromHintText("Int");
		if ((op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" || op == ">>>")
			&& left.getDisplay() == "Int"
			&& right.getDisplay() == "Int")
			return TyType.fromHintText("Int");
		if ((op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=")
			&& (left.getSemanticKey() == right.getSemanticKey() || (left.isNumeric() && right.isNumeric())))
			return TyType.fromHintText("Bool");
		throw new TyperError(filePath, declaration.getPosition(),
			"Bodyless abstract binary operator requires compatible primitive carriers: "
			+ declaration.getIdentity().getCanonicalKey()
			+ " uses "
			+ left.getDisplay()
			+ " and "
			+ right.getDisplay());
	}

	static function permitsResultConversion(actual:TyType, expected:TyType):Bool {
		return actual.getSemanticKey() == expected.getSemanticKey()
			|| expected.isDynamic()
			|| (expected.getDisplay() == "Float" && actual.getDisplay() == "Int");
	}

	/** Return the native result type or diagnose a declaration that cannot implement its claimed result. **/
	public static function validate(info:TyAbstractBinaryOperatorInfo, index:TyperIndex, filePath:String):TyType {
		final declaration = info.getDeclaration();
		final resultType = info.getResultType();
		if (resultType.isUnknown() || resultType.isVoid())
			throw new TyperError(filePath, declaration.getPosition(),
				"Bodyless abstract binary operator requires an explicit value result: " + declaration.getIdentity().getCanonicalKey());
		final left = carrierType(info.getLeftType(), index);
		final right = carrierType(info.getRightType(), index);
		final result = carrierType(resultType, index);
		final baseOperator = HxBinaryOperatorTools.baseOperator(info.getOperator());
		final nativeType = operationType(baseOperator == null ? info.getOperator() : baseOperator, left, right, declaration, filePath);
		if (!permitsResultConversion(nativeType, result))
			throw new TyperError(filePath, declaration.getPosition(),
				"Unsupported abstract binary conversion from "
				+ nativeType.getDisplay()
				+ " to "
				+ result.getDisplay()
				+ " for "
				+ declaration.getIdentity().getCanonicalKey());
		return nativeType;
	}
}
