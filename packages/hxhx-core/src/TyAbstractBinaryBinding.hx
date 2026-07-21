private typedef TyBinaryCandidateMatch = {
	final info:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final score:Int;
	final sourceLeftConversion:TyImplicitConversionPlan;
	final sourceRightConversion:TyImplicitConversionPlan;
	final resultConversion:Null<TyImplicitConversionPlan>;
};

/**
	Selects one exact abstract binary declaration in the shared typer.

	Ranking supports exact semantic identity, numeric widening, declared abstract
	header conversions, and `Dynamic`. The selected operand and compound-result
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

	static function matches(index:TyperIndex, candidates:Array<TyAbstractBinaryOperatorInfo>, leftType:TyType, rightType:TyType, filePath:String,
			position:HxPos):Array<TyBinaryCandidateMatch> {
		final out = new Array<TyBinaryCandidateMatch>();
		for (candidate in candidates) {
			ensureNonGeneric(candidate, filePath, position);
			final directLeft = TyImplicitConversionPlan.select(index, candidate.getLeftType(), leftType);
			final directRight = TyImplicitConversionPlan.select(index, candidate.getRightType(), rightType);
			if (directLeft != null && directRight != null)
				out.push({
					info: candidate,
					reverseArguments: false,
					score: directLeft.getScore() + directRight.getScore(),
					sourceLeftConversion: directLeft,
					sourceRightConversion: directRight,
					resultConversion: null
				});
			if (candidate.getIsCommutative()) {
				final reverseLeft = TyImplicitConversionPlan.select(index, candidate.getRightType(), leftType);
				final reverseRight = TyImplicitConversionPlan.select(index, candidate.getLeftType(), rightType);
				final directScore = directLeft == null || directRight == null ? -1 : directLeft.getScore() + directRight.getScore();
				final reverseScore = reverseLeft == null || reverseRight == null ? -1 : reverseLeft.getScore() + reverseRight.getScore();
				if (reverseLeft != null && reverseRight != null && (directScore < 0 || reverseScore > directScore))
					out.push({
						info: candidate,
						reverseArguments: true,
						score: reverseScore,
						sourceLeftConversion: reverseLeft,
						sourceRightConversion: reverseRight,
						resultConversion: null
					});
			}
		}
		return out;
	}

	static function best(matches:Array<TyBinaryCandidateMatch>, op:String, leftType:TyType, rightType:TyType, filePath:String, position:HxPos,
			requiresWriteback:Bool):Null<TyBoundAbstractBinaryOperator> {
		if (matches.length == 0)
			return null;
		var bestScore = -1;
		for (match in matches)
			if (match.score > bestScore)
				bestScore = match.score;
		final winners = [for (match in matches) if (match.score == bestScore) match];
		if (winners.length > 1) {
			final identities = [
				for (winner in winners)
					winner.info.getDeclaration().getIdentity().getCanonicalKey()
			];
			throw new TyperError(filePath, position,
				"Ambiguous abstract binary operator "
				+ op
				+ " for "
				+ leftType.getDisplay()
				+ " and "
				+ rightType.getDisplay()
				+ "; candidates: "
				+ identities.join(", "));
		}
		final winner = winners[0];
		return new TyBoundAbstractBinaryOperator(op, winner.info, winner.reverseArguments, requiresWriteback, winner.sourceLeftConversion,
			winner.sourceRightConversion, winner.resultConversion);
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
		final explicit = best(matches(index, explicitCandidates, leftType, rightType, filePath, position), op, leftType, rightType, filePath, position, false);
		if (explicit != null)
			return validateBodyless(index, explicit, filePath);

		final baseOperator = HxBinaryOperatorTools.baseOperator(op);
		if (baseOperator != null) {
			final baseCandidates = collect(index, leftType, rightType, baseOperator);
			final baseMatches = new Array<TyBinaryCandidateMatch>();
			for (match in matches(index, baseCandidates, leftType, rightType, filePath, position)) {
				final resultConversion = TyImplicitConversionPlan.select(index, leftType, match.info.getResultType());
				if (resultConversion != null)
					baseMatches.push({
						info: match.info,
						reverseArguments: match.reverseArguments,
						score: match.score,
						sourceLeftConversion: match.sourceLeftConversion,
						sourceRightConversion: match.sourceRightConversion,
						resultConversion: resultConversion
					});
			}
			final fallback = best(baseMatches, op, leftType, rightType, filePath, position, true);
			if (fallback != null)
				return validateBodyless(index, fallback, filePath);
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
