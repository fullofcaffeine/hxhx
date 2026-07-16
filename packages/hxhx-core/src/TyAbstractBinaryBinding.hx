private typedef TyBinaryCandidateMatch = {
	final info:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final score:Int;
};

/**
	Selects one exact abstract binary declaration in the shared typer.

	Ranking currently supports exact semantic identity, declared `Dynamic`, and
	the Haxe numeric widening from `Int` to `Float`. Unsupported conversion search
	fails here with declaration identities in the diagnostic; it never falls back
	to target carriers. Explicit compound declarations are calls without invented
	writeback. Only a missing explicit compound declaration may reuse the matching
	base operator and request shared place/writeback lowering.
**/
class TyAbstractBinaryBinding {
	static function containsTypeParameter(type:TyType):Bool {
		if (type == null)
			return false;
		if (type.isTypeParameter())
			return true;
		if (type.isNullable())
			return containsTypeParameter(type.getNullableInner());
		for (argument in type.getTypeArguments())
			if (containsTypeParameter(argument))
				return true;
		return false;
	}

	static function conversionScore(expected:TyType, actual:TyType):Int {
		if (expected == null || actual == null || expected.isUnknown() || actual.isUnknown())
			return -1;
		if (expected.getSemanticKey() == actual.getSemanticKey())
			return 4;
		if (expected.getSemanticKey() == "dynamic")
			return 1;
		if (expected.getDisplay() == "Float" && actual.getDisplay() == "Int")
			return 3;
		return -1;
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

	static function matches(candidates:Array<TyAbstractBinaryOperatorInfo>, leftType:TyType, rightType:TyType, filePath:String,
			position:HxPos):Array<TyBinaryCandidateMatch> {
		final out = new Array<TyBinaryCandidateMatch>();
		for (candidate in candidates) {
			ensureNonGeneric(candidate, filePath, position);
			final directLeft = conversionScore(candidate.getLeftType(), leftType);
			final directRight = conversionScore(candidate.getRightType(), rightType);
			if (directLeft >= 0 && directRight >= 0)
				out.push({info: candidate, reverseArguments: false, score: directLeft + directRight});
			if (candidate.getIsCommutative()) {
				final reverseLeft = conversionScore(candidate.getRightType(), leftType);
				final reverseRight = conversionScore(candidate.getLeftType(), rightType);
				final directScore = directLeft + directRight;
				final reverseScore = reverseLeft + reverseRight;
				if (reverseLeft >= 0 && reverseRight >= 0 && (!(directLeft >= 0 && directRight >= 0) || reverseScore > directScore))
					out.push({info: candidate, reverseArguments: true, score: reverseScore});
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
		return new TyBoundAbstractBinaryOperator(op, winner.info, winner.reverseArguments, requiresWriteback);
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

	/** Select an exact declaration, or return null when neither operand is an abstract. **/
	public static function select(index:TyperIndex, leftType:TyType, rightType:TyType, op:String, filePath:String,
			position:HxPos):Null<TyBoundAbstractBinaryOperator> {
		if (index == null || leftType == null || rightType == null || !HxBinaryOperatorTools.isAbstractOverloadable(op))
			return null;
		if (!hasAbstractOperand(index, leftType, rightType))
			return null;

		final explicitCandidates = collect(index, leftType, rightType, op);
		final explicit = best(matches(explicitCandidates, leftType, rightType, filePath, position), op, leftType, rightType, filePath, position, false);
		if (explicit != null)
			return explicit;

		final baseOperator = HxBinaryOperatorTools.baseOperator(op);
		if (baseOperator != null) {
			final baseCandidates = collect(index, leftType, rightType, baseOperator);
			final baseMatches = [
				for (match in matches(baseCandidates, leftType, rightType, filePath, position))
					if (conversionScore(leftType, match.info.getResultType()) >= 0) match
			];
			final fallback = best(baseMatches, op, leftType, rightType, filePath, position, true);
			if (fallback != null)
				return fallback;
			if (explicitCandidates.length > 0)
				throw noApplicable(op, leftType, rightType, explicitCandidates, filePath, position);
			if (baseCandidates.length > 0)
				throw noApplicable(op, leftType, rightType, baseCandidates, filePath, position);
		}

		if (HxBinaryOperatorTools.permitsOrdinaryAbstractFallback(op))
			return null;
		throw noApplicable(op, leftType, rightType, explicitCandidates, filePath, position);
	}
}
