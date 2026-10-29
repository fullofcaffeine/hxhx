import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/** Every checked result retains the exact inputs that justified its type. */
private typedef IndexedResultOperand = {
	final source:HxExpr;
	final type:TyType;
}

/**
	A numeric abstract step retains its applied declaration and underlying numeric type.
	`nullableOperand` is present only when the getter is `Null<A>`; the step then
	computes over `A`'s Int storage and its result type stays the original `Null<A>`.
 */
private typedef IndexedNumericStep = {
	final owner:TyAbstractInfo;
	final applied:TyType;
	final storage:TyType;
	final index:TyperIndex;
	final ?nullableOperand:TyIndexedNullableAbstractOperand;
}

/**
	Unary setter permission derived from one registered `CheckedBuiltin` result.
	It retains that exact computed object, the term registered at its distinct
	`computedSource`, and the getter operand from its numeric-step evidence.
 */
private typedef IndexedUnaryAbstractResult = {
	final computed:TyIndexedComputedResult;
	final term:TyInferenceTerm;
	final operand:TyIndexedNullableAbstractOperand;
}

/** Why a computed result fits the original getter place without an executable conversion. */
private enum IndexedPlaceAdmission {
	/** Existing rule: the same type, or an Int result into a nullable Int place. */
	PlaceAssignment;

	/** A unary Int-storage step over `Null<A>` returns that same `Null<A>`; see `admittedUnaryAbstractPlace`. */
	PlaceUnaryNullableAbstract(result:IndexedUnaryAbstractResult);

	/** A selected abstract call returning `A` is assigned to the original `Null<A>` place. */
	PlaceSelectedAbstractResult;
}

/** Why a place result fits the selected setter parameter without an executable conversion. */
private enum IndexedArgumentAdmission {
	/** Existing rule: the same type, or an Int result into a nullable Int parameter. */
	ArgumentAssignment;

	/** Raw `Null<A>` unary result passed to setter parameter `A`, justified only by its own computation chain. */
	ArgumentUnaryNullableAbstract(result:IndexedUnaryAbstractResult, placeTerm:TyInferenceTerm);
}

/** Closed evidence, subordinate to one update query rather than a second operator selector. */
private enum IndexedResultEvidence {
	CheckedBuiltin(operands:Array<IndexedResultOperand>, numericStep:Null<IndexedNumericStep>);
	SelectedCall(binding:TyBoundAbstractBinaryOperator, operands:Array<IndexedResultOperand>, left:TyAbstractBinaryArgument, right:TyAbstractBinaryArgument);
	Converted(input:TyIndexedComputedResult, plan:TyAbstractBinaryConversion);
	CheckedPlace(input:TyIndexedComputedResult, expected:TyType, admission:IndexedPlaceAdmission);
	CheckedArgument(input:TyIndexedComputedResult, expected:TyType, admission:IndexedArgumentAdmission);
}

/**
	Keep operation output distinct from the place conversion and setter argument.
	Only the existing operation/helper owners can construct this evidence. A matching
	display type cannot authorize borrowing a getter term or another update's result.
 */
@:allow(TyperStage)
@:allow(TyIndexedUpdateOperation)
@:allow(TyFunctionInference)
@:allow(TyIndexedUpdateOutcome)
class TyIndexedComputedResult {
	public final query:TyIndexedUpdateQuery;
	public final source:HxExpr;

	final type:TyType;
	final evidence:IndexedResultEvidence;

	function new(query:TyIndexedUpdateQuery, source:HxExpr, type:TyType, evidence:IndexedResultEvidence) {
		this.query = query;
		this.source = source;
		this.type = type;
		this.evidence = evidence;
		requireComplete(type);
	}

	static function requireComplete(type:TyType):Void {
		if (type == null
			|| type.hasUnknownComponent()
			|| type.isUnresolved()
			|| TyTypeSubstitution.parameterIdentities(type).length > 0)
			throw "indexed operation result is not complete yet (haxe_ocaml-rgmu4)";
		if (type.isNullable())
			requireComplete(type.getNullableInner());
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				requireComplete(argument);
			requireComplete(type.getFunctionReturn());
		}
		if (type.isAnonymous())
			for (field in type.getAnonymousFieldTypes())
				requireComplete(field);
		for (argument in type.getTypeArguments())
			requireComplete(argument);
	}

	static function builtin(query:TyIndexedUpdateQuery, type:TyType, operands:Array<IndexedResultOperand>,
			?numericStep:IndexedNumericStep):TyIndexedComputedResult {
		return new TyIndexedComputedResult(query, query.computedSource, type,
			CheckedBuiltin(operands.map(operand -> {source: operand.source, type: operand.type}), numericStep));
	}

	static function selected(query:TyIndexedUpdateQuery, binding:TyBoundAbstractBinaryOperator, type:TyType,
			operands:Array<IndexedResultOperand>):TyIndexedComputedResult {
		if (!switch query.kind {
				case Compound(op): binding.getSourceOperator() == op;
				case _: false;
			})
			throw "indexed operator disagrees with its owned source kind";
		return new TyIndexedComputedResult(query, query.computedSource, type,
			SelectedCall(binding, operands.map(operand -> {source: operand.source, type: operand.type}), binding.getSourceLeftArgument(),
				binding.getSourceRightArgument()));
	}

	static function converted(input:TyIndexedComputedResult, source:HxExpr, plan:TyAbstractBinaryConversion):TyIndexedComputedResult {
		if (plan == null || plan.getActualType().getSemanticKey() != input.type.getSemanticKey())
			throw "indexed conversion has another input type";
		final query = input.query;
		if (!((input.source == query.computedSource && source == query.placeResultSource)
			|| (input.source == query.placeResultSource && source == query.setterInputSource)))
			throw "indexed conversion has a foreign or swapped result query";
		return new TyIndexedComputedResult(query, source, plan.getExpectedType(), Converted(input, plan));
	}

	/** Place compatibility preserves the actual computation; it does not box or unwrap a value. */
	static function admittedPlace(input:TyIndexedComputedResult, expected:TyType):TyIndexedComputedResult {
		if (input.source != input.query.computedSource || !TyNullableIntegerResult.admits(expected, input.type))
			throw "indexed place does not admit its exact computed result";
		return new TyIndexedComputedResult(input.query, input.query.placeResultSource, input.type, CheckedPlace(input, expected, PlaceAssignment));
	}

	/** Retain the selected parameter separately from actual type; target storage transport is not a Haxe conversion. */
	static function admittedArgument(input:TyIndexedComputedResult, expected:TyType):TyIndexedComputedResult {
		if (input.source != input.query.placeResultSource || !TyNullableIntegerResult.admits(expected, input.type))
			throw "indexed argument does not fit its exact selected parameter";
		return new TyIndexedComputedResult(input.query, input.query.setterInputSource, input.type, CheckedArgument(input, expected, ArgumentAssignment));
	}

	/** The checked numeric step over a nullable abstract getter, when this is such a builtin result. */
	function unaryNullableOperand():Null<TyIndexedNullableAbstractOperand>
		return switch evidence {
			case CheckedBuiltin(_, step) if (step != null): step.nullableOperand;
			case _: null;
		};

	/** True when this computed result is a unary Int-storage step over a `Null<A>` getter. */
	function hasUnaryNullableAbstractStep():Bool
		return unaryNullableOperand() != null;

	/**
		Derive unary result permission from this exact, already registered computation.

		The checks are: this object is a `CheckedBuiltin` numeric step at its own
		`computedSource`, it still validates (same query, getter term, applied owner,
		Int storage and unary kind), its static type is the step's declared result (the
		original `Null<A>`), and its occurrence already has a registered term. A result
		that has not been registered, a `SelectedCall`, or a builtin without that exact
		numeric-step evidence cannot derive this permission.
	 */
	function unaryAbstractResult(environment:TyFunctionEnv):IndexedUnaryAbstractResult {
		validate(environment);
		final operand = unaryNullableOperand();
		if (operand == null
			|| source != query.computedSource
			|| operand.query != query
			|| type.getSemanticKey() != operand.originalType.getSemanticKey())
			throw "indexed unary abstract admission requires its exact numeric-step result";
		final term = environment.getInference().sourceTerm(source, environment);
		if (term == null)
			throw "indexed unary abstract admission requires its registered computation";
		return {computed: this, term: term, operand: operand};
	}

	/**
		Admit a unary `Null<A>` result to the identical original getter place.
		The place keeps the derived result permission so the setter step can follow
		exactly this computation, never a different occurrence with an equal type.
	 */
	static function admittedUnaryAbstractPlace(input:TyIndexedComputedResult, expected:TyType, environment:TyFunctionEnv):TyIndexedComputedResult {
		final result = input.unaryAbstractResult(environment);
		if (expected.getSemanticKey() != result.operand.originalType.getSemanticKey())
			throw "indexed unary abstract place has another getter type";
		return new TyIndexedComputedResult(input.query, input.query.placeResultSource, input.type,
			CheckedPlace(input, expected, PlaceUnaryNullableAbstract(result)));
	}

	/** True when a selected abstract call result `A` fits the exact `Null<A>` getter place by assignment. */
	function admitsSelectedAbstractPlace(expected:TyType):Bool {
		final selected = switch evidence {
			case SelectedCall(_, _, _, _): true;
			case _: false;
		};
		if (!selected || source != query.computedSource || expected == null || !expected.isNullable() || type.isNullable() || type.getNominalIdentity() == null)
			return false;
		var inner = expected;
		while (inner.isNullable())
			inner = inner.getNullableInner();
		return inner.getSemanticKey() == type.getSemanticKey();
	}

	/**
		Admit the exact selected compound-call result `A` to its original `Null<A>` place.
		This follows from the retained call result alone; it never uses the getter's
		argument permission. The actual result type stays `A`.
	 */
	static function admittedSelectedAbstractPlace(input:TyIndexedComputedResult, expected:TyType):TyIndexedComputedResult {
		if (!input.admitsSelectedAbstractPlace(expected))
			throw "indexed selected abstract result does not fit its original nullable place";
		return new TyIndexedComputedResult(input.query, input.query.placeResultSource, input.type, CheckedPlace(input, expected, PlaceSelectedAbstractResult));
	}

	/** The unary result permission carried by this place, when it was admitted as such. */
	function unaryAbstractPlaceResult():Null<IndexedUnaryAbstractResult>
		return switch evidence {
			case CheckedPlace(_, _, PlaceUnaryNullableAbstract(result)): result;
			case _: null;
		};

	/** True when this unary place may be passed unchanged to setter parameter `expected`. */
	function admitsUnaryAbstractArgument(expected:TyType):Bool {
		final result = unaryAbstractPlaceResult();
		return result != null && expected != null && result.operand.admits(expected, type);
	}

	/**
		Admit the raw unary `Null<A>` place result to setter parameter `A`.

		The permission is derived only through the input chain: this exact place must
		carry the unary result permission from its own computed predecessor, its
		distinct `placeResultSource` must be registered, and `expected` must be the
		retained applied abstract. The actual setter input type stays `Null<A>`.
	 */
	static function admittedUnaryAbstractArgument(input:TyIndexedComputedResult, expected:TyType, environment:TyFunctionEnv):TyIndexedComputedResult {
		input.validate(environment);
		final result = input.unaryAbstractPlaceResult();
		if (result == null || input.source != input.query.placeResultSource || !result.operand.admits(expected, input.type))
			throw "indexed unary abstract setter admission requires its exact computed unary predecessor";
		final placeTerm = environment.getInference().sourceTerm(input.source, environment);
		if (placeTerm == null)
			throw "indexed unary abstract setter admission requires its registered place result";
		return new TyIndexedComputedResult(input.query, input.query.setterInputSource, input.type,
			CheckedArgument(input, expected, ArgumentUnaryNullableAbstract(result, placeTerm)));
	}

	/** The executable conversion that produced this result from its predecessor; null for an admitted (unconverted) value or an operation. */
	function executableConversion():Null<TyAbstractBinaryConversion>
		return switch evidence {
			case Converted(_, plan): plan;
			case _: null;
		};

	/** The numeric storage a checked abstract increment/decrement computes over; null for ordinary primitive results and selected calls. */
	function storageStep():Null<TyType>
		return switch evidence {
			case CheckedBuiltin(_, step) if (step != null): step.storage;
			case _: null;
		};

	/** The fact this result was derived from; null for the computed operation itself. */
	function predecessor():Null<TyIndexedComputedResult>
		return switch evidence {
			case Converted(input, _) | CheckedPlace(input, _, _) | CheckedArgument(input, _, _): input;
			case CheckedBuiltin(_, _) | SelectedCall(_, _, _, _): null;
		};

	/** Same computed object, query, occurrence, numeric-step operand and registered term as when derived. */
	function validateUnaryResult(result:IndexedUnaryAbstractResult, environment:TyFunctionEnv, inference:TyFunctionInference):Void {
		result.computed.validate(environment, inference);
		if (result.computed.query != query
			|| result.operand.query != query
			|| result.computed.source != query.computedSource
			|| result.computed.unaryNullableOperand() != result.operand
			|| result.computed.type.getSemanticKey() != result.operand.originalType.getSemanticKey()
			|| inference.sourceTerm(query.computedSource, environment) != result.term)
			throw "indexed unary abstract admission changed its computed occurrence or term";
	}

	/** The completed outcome joins this fact to the parameter of its one selected setter. */
	function validatesParameter(expected:TyType):Bool {
		return switch evidence {
			case CheckedArgument(_, parameter, _): parameter.getSemanticKey() == expected.getSemanticKey();
			case Converted(_, plan): plan.getExpectedType().getSemanticKey() == expected.getSemanticKey();
			case _: false;
		};
	}

	/** Current terms must still justify the exact selected result after later constraints. */
	public function validate(environment:TyFunctionEnv, ?retainedInference:TyFunctionInference):Void {
		query.validate(environment.getOwnerIdentity());
		final inference = retainedInference == null ? environment.getInference() : retainedInference;
		switch evidence {
			case CheckedBuiltin(operands, numericStep):
				if (source != query.computedSource)
					throw "builtin result belongs to another indexed query";
				if (numericStep != null) {
					final unary = switch query.kind {
						case Unary(_, _): true;
						case _: false;
					};
					final operand = numericStep.nullableOperand;
					// A nullable getter's step is computed over the applied abstract but
					// keeps the original Null<A> type; otherwise the step type is A itself.
					final declaredResult = operand == null ? numericStep.applied : operand.originalType;
					if (!unary
						|| !numericStep.storage.isNumeric()
						|| declaredResult.getSemanticKey() != type.getSemanticKey()
						|| numericStep.applied.getNominalIdentity() != numericStep.owner.getIdentity()
						|| TyNominalApplication.applyType(numericStep.index, numericStep.owner, numericStep.applied, numericStep.owner.getUnderlyingType())
							.getSemanticKey() != numericStep.storage.getSemanticKey())
						throw "indexed numeric step lost its exact applied declaration";
					if (operand != null) {
						operand.validate(environment, inference);
						if (operand.query != query
							|| operand.owner != numericStep.owner
							|| operand.applied.getSemanticKey() != numericStep.applied.getSemanticKey()
							|| operand.storage.getSemanticKey() != numericStep.storage.getSemanticKey()
							|| operands.length != 1
							|| operands[0].source != query.getterSource
							|| operands[0].type.getSemanticKey() != operand.originalType.getSemanticKey())
							throw "indexed numeric step borrowed another nullable operand";
					}
				}
				for (operand in operands)
					if (inference.expressionType(operand.source, operand.type, environment).getSemanticKey() != operand.type.getSemanticKey())
						throw "indexed builtin operand changed after selection";
			case SelectedCall(binding, operands, left, right):
				final rightSource = switch query.source {
					case EBinop(_, EArrayAccess(_, _), right): right;
					case _: throw "indexed selected call lost its compound source";
				};
				if (binding.getSourceLeftArgument() != left
					|| binding.getSourceRightArgument() != right
					|| operands.length != 2
					|| operands[0].source != query.getterSource
					|| operands[1].source != rightSource
					|| left.getActualType().getSemanticKey() != operands[0].type.getSemanticKey()
					|| right.getActualType().getSemanticKey() != operands[1].type.getSemanticKey())
					throw "indexed operator changed its owned operand conversion";
				// Arguments stay in source order: an admission is valid only at the getter.
				left.validateSource(operands[0].source, environment, inference);
				right.validateSource(operands[1].source, environment, inference);
				for (operand in operands)
					if (inference.expressionType(operand.source, operand.type, environment).getSemanticKey() != operand.type.getSemanticKey())
						throw "indexed selected operator operand changed after selection";
				final callable = inference.directCallType(source, binding.getOperatorInfo().getDeclaration());
				if (source != query.computedSource
					|| callable == null
					|| callable.getFunctionReturn().getSemanticKey() != type.getSemanticKey())
					throw "indexed operator lost its exact call result";
			case Converted(input, plan):
				input.validate(environment, inference);
				if (input.query != query
					|| plan.getActualType().getSemanticKey() != input.type.getSemanticKey()
					|| plan.getExpectedType().getSemanticKey() != type.getSemanticKey())
					throw "indexed conversion result no longer fits its selected input";
			case CheckedPlace(input, expected, admission):
				input.validate(environment, inference);
				if (input.query != query
					|| input.source != query.computedSource
					|| source != query.placeResultSource
					|| type.getSemanticKey() != input.type.getSemanticKey()
					|| inference.expressionType(query.getterSource, expected, environment).getSemanticKey() != expected.getSemanticKey())
					throw "indexed checked place lost its actual result or original getter type";
				final admitted = switch admission {
					case PlaceAssignment:
						TyNullableIntegerResult.admits(expected, input.type);
					case PlaceUnaryNullableAbstract(result): validateUnaryResult(result, environment,
							inference); result.computed == input && expected.getSemanticKey() == result.operand.originalType.getSemanticKey();
					case PlaceSelectedAbstractResult:
						input.admitsSelectedAbstractPlace(expected);
				};
				if (!admitted)
					throw "indexed checked place no longer admits its exact computed result";
			case CheckedArgument(input, expected, admission):
				input.validate(environment, inference);
				if (input.query != query
					|| input.source != query.placeResultSource
					|| source != query.setterInputSource
					|| type.getSemanticKey() != input.type.getSemanticKey())
					throw "indexed checked argument lost its actual result or selected parameter";
				final admitted = switch admission {
					case ArgumentAssignment:
						TyNullableIntegerResult.admits(expected, input.type);
					case ArgumentUnaryNullableAbstract(result, placeTerm): validateUnaryResult(result, environment,
							inference); input.unaryAbstractPlaceResult() == result && inference.sourceTerm(query.placeResultSource,
							environment) == placeTerm && result.operand.admits(expected, type);
				};
				if (!admitted)
					throw "indexed checked argument no longer fits its exact selected parameter";
		}
		if (inference.expressionType(source, type, environment).getSemanticKey() != type.getSemanticKey())
			throw "indexed result changed after selection";
	}

	public function getType(environment:TyFunctionEnv):TyType {
		validate(environment);
		return type;
	}

	/** This query must be registered only in its transaction's candidate inference state. */
	function register(trial:TyIndexedUpdateTrial, environment:TyFunctionEnv):Void {
		validate(environment);
		environment.getInference().recordIndexedComputed(trial, this, environment);
	}
}
