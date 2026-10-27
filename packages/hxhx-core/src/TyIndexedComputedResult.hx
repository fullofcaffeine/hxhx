import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/** Every checked result retains the exact inputs that justified its type. */
private typedef IndexedResultOperand = {
	final source:HxExpr;
	final type:TyType;
}

/** A numeric abstract step retains its applied declaration and underlying numeric type. */
private typedef IndexedNumericStep = {
	final owner:TyAbstractInfo;
	final applied:TyType;
	final storage:TyType;
	final index:TyperIndex;
}

/** Closed evidence, subordinate to one update query rather than a second operator selector. */
private enum IndexedResultEvidence {
	CheckedBuiltin(operands:Array<IndexedResultOperand>, numericStep:Null<IndexedNumericStep>);
	SelectedCall(binding:TyBoundAbstractBinaryOperator, operands:Array<IndexedResultOperand>, left:TyAbstractBinaryConversion,
		right:TyAbstractBinaryConversion);
	Converted(input:TyIndexedComputedResult, plan:TyAbstractBinaryConversion);
	CheckedPlace(input:TyIndexedComputedResult, expected:TyType);
	CheckedArgument(input:TyIndexedComputedResult, expected:TyType);
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
			SelectedCall(binding, operands.map(operand -> {source: operand.source, type: operand.type}), binding.getSourceLeftConversion(),
				binding.getSourceRightConversion()));
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
		return new TyIndexedComputedResult(input.query, input.query.placeResultSource, input.type, CheckedPlace(input, expected));
	}

	/** Retain the selected parameter separately from actual type; target storage transport is not a Haxe conversion. */
	static function admittedArgument(input:TyIndexedComputedResult, expected:TyType):TyIndexedComputedResult {
		if (input.source != input.query.placeResultSource || !TyNullableIntegerResult.admits(expected, input.type))
			throw "indexed argument does not fit its exact selected parameter";
		return new TyIndexedComputedResult(input.query, input.query.setterInputSource, input.type, CheckedArgument(input, expected));
	}

	/** The completed outcome joins this fact to the parameter of its one selected setter. */
	function validatesParameter(expected:TyType):Bool {
		return switch evidence {
			case CheckedArgument(_, parameter): parameter.getSemanticKey() == expected.getSemanticKey();
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
					if (!unary
						|| !numericStep.storage.isNumeric()
						|| numericStep.applied.getSemanticKey() != type.getSemanticKey()
						|| numericStep.applied.getNominalIdentity() != numericStep.owner.getIdentity()
						|| TyNominalApplication.applyType(numericStep.index, numericStep.owner, numericStep.applied, numericStep.owner.getUnderlyingType())
							.getSemanticKey() != numericStep.storage.getSemanticKey())
						throw "indexed numeric step lost its exact applied declaration";
				}
				for (operand in operands)
					if (inference.expressionType(operand.source, operand.type, environment).getSemanticKey() != operand.type.getSemanticKey())
						throw "indexed builtin operand changed after selection";
			case SelectedCall(binding, operands, left, right):
				final rightSource = switch query.source {
					case EBinop(_, EArrayAccess(_, _), right): right;
					case _: throw "indexed selected call lost its compound source";
				};
				if (binding.getSourceLeftConversion() != left
					|| binding.getSourceRightConversion() != right
					|| operands.length != 2
					|| operands[0].source != query.getterSource
					|| operands[1].source != rightSource
					|| left.getActualType().getSemanticKey() != operands[0].type.getSemanticKey()
					|| right.getActualType().getSemanticKey() != operands[1].type.getSemanticKey())
					throw "indexed operator changed its owned operand conversion";
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
			case CheckedPlace(input, expected):
				input.validate(environment, inference);
				if (input.query != query
					|| input.source != query.computedSource
					|| source != query.placeResultSource
					|| type.getSemanticKey() != input.type.getSemanticKey()
					|| !TyNullableIntegerResult.admits(expected, input.type)
					|| inference.expressionType(query.getterSource, expected, environment).getSemanticKey() != expected.getSemanticKey())
					throw "indexed checked place lost its actual result or original getter type";
			case CheckedArgument(input, expected):
				input.validate(environment, inference);
				if (input.query != query
					|| input.source != query.placeResultSource
					|| source != query.setterInputSource
					|| type.getSemanticKey() != input.type.getSemanticKey()
					|| !TyNullableIntegerResult.admits(expected, input.type))
					throw "indexed checked argument lost its actual result or selected parameter";
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
