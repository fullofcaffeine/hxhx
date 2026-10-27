/** Runtime value ownership is independent of the setter-authoritative source type. */
enum TyIndexedUpdatePayload {
	OldGetter;
	SetterValue;
}

/** Raw call admission is retained separately from its final converted argument list. */
typedef TyIndexedSetterAdmission = {
	final declaration:TyDeclarationInfo;
	final signature:TyFunSig;
	final order:TyMethodArgumentOrder;
	final sources:Array<HxExpr>;
	final types:Array<TyType>;
	final inputTrial:Null<TyMethodInputState.TyMethodInputTrial>;
}

/**
	A checked update combines the foundation's exact helper identities with result evidence.
	The identity-only transaction fixture cannot construct this class or authorize
	projection. Public source admission remains disabled until shared projection is reviewed.
 */
@:allow(TyperStage)
@:allow(TyFunctionInference)
class TyIndexedUpdateOutcome {
	public final selection:TyIndexedUpdateSelection;
	public final computed:TyIndexedComputedResult;
	public final placeResult:TyIndexedComputedResult;
	public final setterInput:TyIndexedComputedResult;
	public final payload:TyIndexedUpdatePayload;

	final admission:TyIndexedSetterAdmission;
	final environment:TyFunctionEnv;
	final index:TyperIndex;
	final finalSources:Array<HxExpr>;
	final finalTypes:Array<TyType>;

	function new(input:{
		selection:TyIndexedUpdateSelection,
		computed:TyIndexedComputedResult,
		placeResult:TyIndexedComputedResult,
		setterInput:TyIndexedComputedResult,
		admission:TyIndexedSetterAdmission,
		environment:TyFunctionEnv,
		index:TyperIndex,
		finalTypes:Array<TyType>
	}) {
		selection = input.selection;
		computed = input.computed;
		placeResult = input.placeResult;
		setterInput = input.setterInput;
		admission = {
			declaration: input.admission.declaration,
			signature: input.admission.signature,
			order: input.admission.order,
			sources: input.admission.sources.copy(),
			types: input.admission.types.copy(),
			inputTrial: input.admission.inputTrial
		};
		environment = input.environment;
		index = input.index;
		finalSources = selection.setter.getArguments();
		finalTypes = input.finalTypes.copy();
		payload = switch selection.query.kind {
			case Unary(_, Postfix): OldGetter;
			case _: SetterValue;
		};
		validate(environment.getInference());
	}

	/** Validate final actuals against the retained declaration and order without another search. */
	function validate(inference:TyFunctionInference):Void {
		final query = selection.query;
		selection.validate(environment.getOwnerIdentity());
		if (computed.query != query
			|| placeResult.query != query
			|| setterInput.query != query
			|| computed.source != query.computedSource
			|| placeResult.source != query.placeResultSource
			|| setterInput.source != query.setterInputSource
			|| admission.declaration != selection.setter.declaration)
			throw "indexed outcome has foreign result or declaration evidence";
		for (result in [computed, placeResult, setterInput])
			result.validate(environment, inference);
		final arguments = selection.setter.getArguments();
		if (arguments.length != finalSources.length
			|| arguments.length != finalTypes.length
			|| arguments.length != admission.sources.length
			|| arguments.length != admission.types.length)
			throw "indexed setter lost its selected argument order";
		final parameters = admission.order.sourceContexts(TyMethodGenericBinding.specializeParameters(admission.declaration, admission.signature,
			admission.order.rankedTypes(admission.types), index));
		final valueIndex = arguments.length - 1;
		for (offset in 0...arguments.length) {
			if (arguments[offset] != finalSources[offset]
				|| arguments[offset] != (offset == valueIndex ? query.setterInputSource : admission.sources[offset]))
				throw "indexed setter has swapped or foreign final arguments";
			final actual = inference.expressionType(arguments[offset], finalTypes[offset], environment);
			if (offset == valueIndex && actual.getSemanticKey() != setterInput.type.getSemanticKey())
				throw "indexed setter input differs from its selected conversion output";
			if (parameters[offset] == null || !TyValueCompatibility.accepts(index, parameters[offset], actual, arguments[offset]))
				throw "indexed setter result no longer fits its selected parameter";
		}
	}

	public function getStaticType(scope:TyFunctionEnv):TyType {
		selection.query.validate(scope.getOwnerIdentity());
		validate(scope.getInference());
		return scope.getInference().expressionType(selection.query.setterSource, admission.signature.getReturnType(), scope);
	}
}
