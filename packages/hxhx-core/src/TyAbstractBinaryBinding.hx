private typedef TyBinaryCandidateMatch = {
	final info:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final sourceLeftConversion:TyAbstractBinaryConversion;
	final sourceRightConversion:TyAbstractBinaryConversion;
	final resultConversion:Null<TyAbstractBinaryConversion>;
};

/**
	Selects one exact abstract binary declaration in the shared typer.

	Declarations are tried in source order, with the left abstract before the right.
	The first applicable declaration wins; conversion scores only choose argument
	orientation within one commutative declaration. The selected operand and compound-result
	conversion plans travel with the binding, so shared lowering does not repeat
	overload logic and backends never infer conversions from target carriers.
	Explicit compound declarations are calls without invented writeback. Only a
	missing explicit compound declaration may reuse the matching base operator and
	request shared place/writeback lowering.
**/
class TyAbstractBinaryBinding {
	static function validateBodyless(index:TyperIndex, binding:TyBoundAbstractBinaryOperator, filePath:String):TyBoundAbstractBinaryOperator {
		final info = binding.getOperatorInfo();
		if (!info.getDeclaration().getHasBody())
			TyAbstractNativeBinaryOperation.validate(info, index, filePath);
		return binding;
	}

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

	static function collect(index:TyperIndex, leftType:TyType, rightType:TyType, op:String):Array<TyAbstractBinaryOperatorInfo> {
		final out = new Array<TyAbstractBinaryOperatorInfo>();
		final seen = new haxe.ds.StringMap<Bool>();
		for (operandType in [leftType, rightType]) {
			final identity = operandType == null ? null : operandType.getNominalIdentity();
			final info = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
			if (info == null)
				continue;
			for (candidate in info.getBinaryOperators(op)) {
				final key = candidate.getDeclaration().getIdentity().getCanonicalKey();
				if (!seen.exists(key)) {
					seen.set(key, true);
					out.push(candidate);
				}
			}
		}
		return out;
	}

	static function hasAbstractOperand(index:TyperIndex, leftType:TyType, rightType:TyType):Bool {
		for (operandType in [leftType, rightType]) {
			final identity = operandType == null ? null : operandType.getNominalIdentity();
			if (identity != null && index.getAbstractByFullName(identity.getCanonicalName()) != null)
				return true;
		}
		return false;
	}

	static function ensureNonGeneric(candidate:TyAbstractBinaryOperatorInfo, filePath:String, position:HxPos):Void {
		final declaration = candidate.getDeclaration();
		final owner = declaration.getOwner();
		if (declaration.getTypeParameters().length > 0
			|| containsTypeParameter(candidate.getLeftType())
			|| containsTypeParameter(candidate.getRightType())
			|| containsTypeParameter(candidate.getResultType()))
			throw new TyperError(filePath, position,
				"Generic abstract binary operator is not supported yet: "
				+ owner.getCanonicalName()
				+ " via "
				+ declaration.getIdentity().getCanonicalKey());
	}

	/** Keep declaration order; conversion quality only chooses one declaration's orientation. */
	static function firstMatch(index:TyperIndex, candidates:Array<TyAbstractBinaryOperatorInfo>, leftType:TyType, rightType:TyType, filePath:String,
			position:HxPos):Null<TyBinaryCandidateMatch> {
		for (candidate in candidates) {
			ensureNonGeneric(candidate, filePath, position);
			final directLeft = TyAbstractBinaryConversion.select(index, candidate.getLeftType(), leftType);
			final directRight = TyAbstractBinaryConversion.select(index, candidate.getRightType(), rightType);
			final directScore = directLeft == null || directRight == null ? -1 : directLeft.getScore() + directRight.getScore();
			if (candidate.getIsCommutative()) {
				final reverseLeft = TyAbstractBinaryConversion.select(index, candidate.getRightType(), leftType);
				final reverseRight = TyAbstractBinaryConversion.select(index, candidate.getLeftType(), rightType);
				final reverseScore = reverseLeft == null || reverseRight == null ? -1 : reverseLeft.getScore() + reverseRight.getScore();
				if (reverseScore > directScore)
					return {
						info: candidate,
						reverseArguments: true,
						sourceLeftConversion: reverseLeft,
						sourceRightConversion: reverseRight,
						resultConversion: null
					};
			}
			if (directScore >= 0)
				return {
					info: candidate,
					reverseArguments: false,
					sourceLeftConversion: directLeft,
					sourceRightConversion: directRight,
					resultConversion: null
				};
		}
		return null;
	}

	static function bind(match:TyBinaryCandidateMatch, op:String, requiresWriteback:Bool):TyBoundAbstractBinaryOperator {
		return new TyBoundAbstractBinaryOperator(op, match.info, match.reverseArguments, requiresWriteback, match.sourceLeftConversion,
			match.sourceRightConversion, match.resultConversion);
	}

	static function noApplicable(op:String, leftType:TyType, rightType:TyType, candidates:Array<TyAbstractBinaryOperatorInfo>, filePath:String,
			position:HxPos):TyperError {
		var detail = "";
		if (candidates.length == 1) {
			final candidate = candidates[0];
			detail = "; candidate "
				+ candidate.getDeclaration().getIdentity().getCanonicalKey()
				+ " requires "
				+ candidate.getLeftType().getDisplay()
				+ " and "
				+ candidate.getRightType().getDisplay();
		}
		return new TyperError(filePath, position,
			"No applicable abstract binary operator "
			+ op
			+ " for "
			+ leftType.getDisplay()
			+ " and "
			+ rightType.getDisplay()
			+ detail);
	}

	/** Ordinary Haxe operations that remain legal after overload lookup misses. **/
	public static function permitsOrdinaryFallback(op:String, leftType:TyType, rightType:TyType):Bool {
		if (HxBinaryOperatorTools.permitsOrdinaryAbstractFallback(op))
			return true;
		if (op == "+=" && leftType != null && leftType.getSemanticKey() == "primitive:String")
			return true;
		return op == "+"
			&& ((leftType != null && leftType.getDisplay() == "String") || (rightType != null && rightType.getDisplay() == "String"));
	}

	/** Select an exact declaration, or return null when neither operand is an abstract. **/
	public static function select(index:TyperIndex, leftType:TyType, rightType:TyType, op:String, filePath:String,
			position:HxPos):Null<TyBoundAbstractBinaryOperator> {
		if (index == null || leftType == null || rightType == null || !HxBinaryOperatorTools.isAbstractOverloadable(op))
			return null;
		if (!hasAbstractOperand(index, leftType, rightType))
			return null;

		final explicitCandidates = collect(index, leftType, rightType, op);
		final explicit = firstMatch(index, explicitCandidates, leftType, rightType, filePath, position);
		if (explicit != null)
			return validateBodyless(index, bind(explicit, op, false), filePath);

		final baseOperator = HxBinaryOperatorTools.baseOperator(op);
		if (baseOperator != null) {
			final baseCandidates = collect(index, leftType, rightType, baseOperator);
			final match = firstMatch(index, baseCandidates, leftType, rightType, filePath, position);
			if (match != null) {
				final resultConversion = TyAbstractBinaryConversion.select(index, leftType, match.info.getResultType());
				// A selected base operator must fit the destination. Do not silently
				// select a later declaration merely because its result would fit.
				if (resultConversion == null)
					throw noApplicable(op, leftType, rightType, [match.info], filePath, position);
				return validateBodyless(index, bind({
					info: match.info,
					reverseArguments: match.reverseArguments,
					sourceLeftConversion: match.sourceLeftConversion,
					sourceRightConversion: match.sourceRightConversion,
					resultConversion: resultConversion
				}, op, true), filePath);
			}
			// Inapplicable numeric overloads on the right do not forbid appending
			// that value to a String. Applicable authored operators still win above.
			if (permitsOrdinaryFallback(op, leftType, rightType))
				return null;
			if (explicitCandidates.length > 0)
				throw noApplicable(op, leftType, rightType, explicitCandidates, filePath, position);
			if (baseCandidates.length > 0)
				throw noApplicable(op, leftType, rightType, baseCandidates, filePath, position);
		}

		if (permitsOrdinaryFallback(op, leftType, rightType))
			return null;
		throw noApplicable(op, leftType, rightType, explicitCandidates, filePath, position);
	}
}
