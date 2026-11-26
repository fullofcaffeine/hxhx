private typedef TyBinaryCandidateMatch = {
	final info:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final sourceLeftArgument:TyAbstractBinaryArgument;
	final sourceRightArgument:TyAbstractBinaryArgument;
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

	/**
		The operator with its own type parameters bound to the operands that its first and second
		parameters receive. Haxe 4.3.7 gives each such parameter a constrained monomorph and unifies
		the operands with the mapped argument types (`operators.ml`, lines 466-520), so UInt's
		`equalsInt<T:Int>(a:UInt, b:T)` serves `u == 3` with T = Int. Null when an operand breaks a
		parameter's constraint (the declaration does not apply). A type parameter used anywhere but
		as a whole parameter type is still unsupported (`ensureNonGeneric`).
	**/
	static function instantiate(index:TyperIndex, candidate:TyAbstractBinaryOperatorInfo, firstOperand:TyType, secondOperand:TyType, filePath:String,
			position:HxPos):Null<TyAbstractBinaryOperatorInfo> {
		final declaration = candidate.getDeclaration();
		final parameters = declaration.getTypeParameterIds();
		if (parameters.length == 0) {
			ensureNonGeneric(candidate, filePath, position);
			return candidate;
		}
		final bindings = new haxe.ds.StringMap<TyType>();
		for (pair in [
			{declared: candidate.getLeftType(), actual: firstOperand},
			{declared: candidate.getRightType(), actual: secondOperand}
		]) {
			final parameter = pair.declared.getTypeParameterIdentity();
			if (parameter == null || parameters.filter(owned -> owned.equals(parameter)).length == 0) {
				if (containsTypeParameter(pair.declared))
					ensureNonGeneric(candidate, filePath, position);
				continue;
			}
			if (pair.actual == null || pair.actual.hasUnknownComponent())
				return null;
			final key = parameter.getCanonicalKey();
			if (!bindings.exists(key))
				bindings.set(key, pair.actual);
		}
		final constraints = declaration.getResolvedTypeParameterConstraints();
		for (parameter in parameters) {
			final key = parameter.getCanonicalKey();
			if (!bindings.exists(key))
				ensureNonGeneric(candidate, filePath, position);
			final bounds = constraints.exists(key) ? constraints.get(key) : [];
			for (bound in bounds)
				if (TyAbstractBinaryConversion.select(index, bound, bindings.get(key)) == null)
					return null;
		}
		final result = TyTypeSubstitution.apply(candidate.getResultType(), bindings);
		if (containsTypeParameter(result))
			ensureNonGeneric(candidate, filePath, position);
		return new TyAbstractBinaryOperatorInfo(candidate.getOperator(), declaration, TyTypeSubstitution.apply(candidate.getLeftType(), bindings),
			TyTypeSubstitution.apply(candidate.getRightType(), bindings), result, candidate.getIsCommutative());
	}

	/** Keep declaration order; conversion quality only chooses one declaration's orientation. */
	static function firstMatch(index:TyperIndex, candidates:Array<TyAbstractBinaryOperatorInfo>, leftType:TyType, rightType:TyType, filePath:String,
			position:HxPos, ?indexedLeft:TyIndexedNullableAbstractOperand):Null<TyBinaryCandidateMatch> {
		for (generic in candidates) {
			// Each orientation binds the operator's own type parameters from its operands.
			final candidate = instantiate(index, generic, leftType, rightType, filePath, position);
			final directLeft = candidate == null ? null : argument(index, candidate.getLeftType(), leftType, indexedLeft);
			final directRight = candidate == null ? null : argument(index, candidate.getRightType(), rightType);
			final directScore = directLeft == null || directRight == null ? -1 : directLeft.getScore() + directRight.getScore();
			if (generic.getIsCommutative()) {
				final reversed = instantiate(index, generic, rightType, leftType, filePath, position);
				final reverseLeft = reversed == null ? null : argument(index, reversed.getRightType(), leftType, indexedLeft);
				final reverseRight = reversed == null ? null : argument(index, reversed.getLeftType(), rightType);
				final reverseScore = reverseLeft == null || reverseRight == null ? -1 : reverseLeft.getScore() + reverseRight.getScore();
				if (reverseScore > directScore)
					return {
						info: reversed,
						reverseArguments: true,
						sourceLeftArgument: reverseLeft,
						sourceRightArgument: reverseRight,
						resultConversion: null
					};
			}
			if (directScore >= 0)
				return {
					info: candidate,
					reverseArguments: false,
					sourceLeftArgument: directLeft,
					sourceRightArgument: directRight,
					resultConversion: null
				};
		}
		return null;
	}

	/**
		Match one operand to one declared parameter. Existing executable conversions are
		tried first against the raw actual type, so every ordinary result is unchanged.
		Only when none applies may the checked indexed getter be admitted, and only to
		its exact applied abstract. Callers pass `operand` for the source-left getter
		position only, whichever declaration parameter that position is oriented to.
	 */
	static function argument(index:TyperIndex, expected:TyType, actual:TyType, ?operand:TyIndexedNullableAbstractOperand):Null<TyAbstractBinaryArgument> {
		final plan = TyAbstractBinaryConversion.select(index, expected, actual);
		if (plan != null)
			return TyAbstractBinaryArgument.converted(plan);
		return operand != null && operand.admits(expected, actual) ? TyAbstractBinaryArgument.indexed(operand, expected) : null;
	}

	static function bind(match:TyBinaryCandidateMatch, op:String, requiresWriteback:Bool):TyBoundAbstractBinaryOperator {
		return new TyBoundAbstractBinaryOperator(op, match.info, match.reverseArguments, requiresWriteback, match.sourceLeftArgument,
			match.sourceRightArgument, match.resultConversion);
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

	/**
		Whether an abstract operand declares an operator for `op` or for its base operator
		(`+` for `+=`). A compound failure on such an abstract comes from that declaration,
		as for `haxe.Int32`; an abstract without one fails for another reason.
	**/
	public static function declaresOperator(index:TyperIndex, leftType:TyType, rightType:TyType, op:String):Bool {
		if (index == null || leftType == null || rightType == null)
			return false;
		final baseOperator = HxBinaryOperatorTools.baseOperator(op);
		return collect(index, leftType, rightType, op).length > 0
			|| (baseOperator != null && collect(index, leftType, rightType, baseOperator).length > 0);
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
			position:HxPos):Null<TyBoundAbstractBinaryOperator>
		return selectWithOperand(index, leftType, rightType, op, filePath, position);

	/**
		Indexed-update entry over the same catalog, declaration order, orientation and
		generic rejection as `select`.

		`leftType` is the raw source-left getter type. When `operand` is present it must
		describe exactly that type; its applied abstract is then visible to declaration
		lookup, and it may be admitted unchanged to a parameter of that same applied
		abstract. The right-hand operand never receives this permission.
	 */
	public static function selectIndexed(index:TyperIndex, leftType:TyType, rightType:TyType, op:String, filePath:String, position:HxPos,
			operand:Null<TyIndexedNullableAbstractOperand>):Null<TyBoundAbstractBinaryOperator> {
		if (operand != null && operand.originalType.getSemanticKey() != leftType.getSemanticKey())
			throw "indexed binary lookup has another original getter type";
		return selectWithOperand(index, leftType, rightType, op, filePath, position, operand);
	}

	static function selectWithOperand(index:TyperIndex, leftType:TyType, rightType:TyType, op:String, filePath:String, position:HxPos,
			?indexedLeft:TyIndexedNullableAbstractOperand):Null<TyBoundAbstractBinaryOperator> {
		if (index == null || leftType == null || rightType == null || !HxBinaryOperatorTools.isAbstractOverloadable(op))
			return null;
		final lookupLeft = indexedLeft == null ? leftType : indexedLeft.applied;
		if (!hasAbstractOperand(index, lookupLeft, rightType))
			return null;

		final explicitCandidates = collect(index, lookupLeft, rightType, op);
		final explicit = firstMatch(index, explicitCandidates, leftType, rightType, filePath, position, indexedLeft);
		if (explicit != null)
			return validateBodyless(index, bind(explicit, op, false), filePath);

		final baseOperator = HxBinaryOperatorTools.baseOperator(op);
		if (baseOperator != null) {
			final baseCandidates = collect(index, lookupLeft, rightType, baseOperator);
			final match = firstMatch(index, baseCandidates, leftType, rightType, filePath, position, indexedLeft);
			if (match != null) {
				final resultConversion = TyAbstractBinaryConversion.select(index, leftType, match.info.getResultType());
				// A selected base operator must fit the destination. Do not silently
				// select a later declaration merely because its result would fit.
				if (resultConversion == null)
					throw noApplicable(op, leftType, rightType, [match.info], filePath, position);
				return validateBodyless(index, bind({
					info: match.info,
					reverseArguments: match.reverseArguments,
					sourceLeftArgument: match.sourceLeftArgument,
					sourceRightArgument: match.sourceRightArgument,
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
		// No declared operator at all: one abstract operand may act through its `to`
		// primitive, as upstream allows; the caller then types the operation.
		// A compound whose place is the abstract would also need a write-back through
		// `from`; that is not lowered yet, so only a value operand may use this rule.
		final base = baseOperator == null ? op : baseOperator;
		final abstractPlace = baseOperator != null && TyAbstractPrimitiveOperation.view(index, lookupLeft) != null;
		if (explicitCandidates.length == 0
			&& !abstractPlace
			&& TyAbstractPrimitiveOperation.operation(index, base, lookupLeft, rightType) != null)
			return null;
		throw noApplicable(op, leftType, rightType, explicitCandidates, filePath, position);
	}
}
