/**
	Selects one exact non-generic abstract unary declaration in the shared typer.

	This class owns semantic selection only. It never chooses a target carrier,
	infers behavior from a helper name, or assigns prefix/postfix mutation rules.
	The selected declaration and its declared result type are later lowered into
	an exact call or an explicit shared typed block before backend emission.
**/
class TyAbstractUnaryBinding {
	static function containsTypeParameter(type:TyType):Bool {
		if (type == null)
			return false;
		if (type.isTypeParameter())
			return true;
		if (type.isNullable())
			return containsTypeParameter(type.getNullableInner());
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				if (containsTypeParameter(argument))
					return true;
			return containsTypeParameter(type.getFunctionReturn());
		}
		for (argument in type.getTypeArguments())
			if (containsTypeParameter(argument))
				return true;
		return false;
	}

	static function operatorLabel(op:HxUnaryOperator, fixity:HxUnaryFixity):String {
		return (fixity == HxUnaryFixity.Prefix ? "prefix " : "postfix ") + HxUnaryOperatorTools.sourceToken(op);
	}

	static function unsupportedGeneric(filePath:String, position:HxPos, operandType:TyType, declaration:TyDeclarationInfo):TyperError {
		return new TyperError(filePath, position,
			"Generic abstract unary operator is not supported yet for "
			+ operandType.getDisplay()
			+ ": "
			+ declaration.getIdentity().getCanonicalKey());
	}

	/**
		Return the exact declaration for an abstract operand, or null when the
		operand is not an abstract. Abstract failures are always diagnosed here;
		they never fall through to a primitive carrier operation.
	**/
	public static function select(index:TyperIndex, operandType:TyType, op:HxUnaryOperator, fixity:HxUnaryFixity, filePath:String,
			position:HxPos):Null<TyAbstractOperatorInfo> {
		if (index == null || operandType == null)
			return null;
		final identity = operandType.getNominalIdentity();
		if (identity == null)
			return null;
		final abstractInfo = index.getAbstractByFullName(identity.getCanonicalName());
		if (abstractInfo == null)
			return null;

		final candidates = abstractInfo.getUnaryOperators(op, fixity);
		if (candidates.length == 0)
			throw new TyperError(filePath, position, "No applicable abstract unary operator "
				+ operatorLabel(op, fixity)
				+ " for "
				+ operandType.getDisplay());

		final applicable = new Array<TyAbstractOperatorInfo>();
		for (candidate in candidates) {
			final declaration = candidate.getDeclaration();
			if (abstractInfo.getTypeParameters().length > 0
				|| declaration.getTypeParameters().length > 0
				|| containsTypeParameter(candidate.getOperandType())
				|| containsTypeParameter(candidate.getResultType()))
				throw unsupportedGeneric(filePath, position, operandType, declaration);
			if (candidate.getOperandType().getSemanticKey() == operandType.getSemanticKey())
				applicable.push(candidate);
		}

		if (applicable.length == 0)
			throw new TyperError(filePath, position, "No applicable abstract unary operator "
				+ operatorLabel(op, fixity)
				+ " for "
				+ operandType.getDisplay());
		if (applicable.length > 1) {
			final identities = [
				for (candidate in applicable)
					candidate.getDeclaration().getIdentity().getCanonicalKey()
			];
			throw new TyperError(filePath, position,
				"Ambiguous abstract unary operator "
				+ operatorLabel(op, fixity)
				+ " for "
				+ operandType.getDisplay()
				+ "; candidates: "
				+ identities.join(", "));
		}
		return applicable[0];
	}
}
