import TyIndexedUpdateOutcome.TyIndexedUpdatePayload;
import TyIndexedUpdateSelection.TyIndexedUpdateKind;
import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/** How the saved getter value becomes the value the setter stores. */
enum TyIndexedUpdateStep {
	/** Ordinary primitive operation on the getter value (and the right operand for a compound update). */
	Primitive(op:String, result:TyType);

	/**
		Increment/decrement over an abstract's numeric storage, as upstream types it.
		The getter value is viewed as `storage` for the step; the result keeps the
		getter's own, possibly nullable, abstract type. No declared helper is called.
	 */
	StorageView(op:String, storage:TyType, result:TyType);

	/**
		The exact selected declared operator. `left` and `right` are the executable
		conversions for the source-left (getter) and source-right operands, or null
		when the operand is admitted unchanged (the raw nullable getter value).
	 */
	Selected(binding:TyBoundAbstractBinaryOperator, left:Null<TyAbstractBinaryConversion>, right:Null<TyAbstractBinaryConversion>, result:TyType);
}

/**
	Closed projection facts for one completed indexed update (`a[i]++`, `--a[i]`, `a[i] op= v`
	on an abstract with declared indexed helpers).

	Why: the typer has already selected and validated the getter, the operation and
	the setter (`TyIndexedUpdateOutcome`). The typed body builder must turn that into
	ordinary typed nodes without re-selecting declarations or inventing conversions.
	This plan is the only way those facts leave the outcome, and only
	`TyIndexedUpdateOutcome.projection` can create it after revalidation.

	What it carries: the update query (source occurrences), kind and result payload
	owner, the static type (the setter's return type), the getter's actual result
	type, the step, the executable place/setter-input conversions (null when the
	value is admitted raw), and the setter's call plan: declaration, source operands
	in selected order (the last one is `query.setterInputSource`), expected argument
	contexts, implicit argument conversions and named-argument plan, exactly as the
	type resolver publishes them for the selected getter. Temporaries are allocated by
	the projecting function body, not named here.
 */
class TyIndexedUpdatePlan {
	public final query:TyIndexedUpdateQuery;
	public final kind:TyIndexedUpdateKind;
	public final payload:TyIndexedUpdatePayload;
	public final staticType:TyType;
	public final getterType:TyType;
	public final step:TyIndexedUpdateStep;
	public final placeConversion:Null<TyAbstractBinaryConversion>;
	public final setterConversion:Null<TyAbstractBinaryConversion>;
	public final setterDeclaration:TyDeclarationInfo;
	public final setterSources:Array<HxExpr>;
	public final setterCall:TypedCallResolution;

	@:allow(TyIndexedUpdateOutcome)
	function new(input:{
		query:TyIndexedUpdateQuery,
		payload:TyIndexedUpdatePayload,
		staticType:TyType,
		getterType:TyType,
		step:TyIndexedUpdateStep,
		placeConversion:Null<TyAbstractBinaryConversion>,
		setterConversion:Null<TyAbstractBinaryConversion>,
		setterDeclaration:TyDeclarationInfo,
		setterSources:Array<HxExpr>,
		setterCall:TypedCallResolution
	}) {
		query = input.query;
		kind = query.kind;
		payload = input.payload;
		staticType = input.staticType;
		getterType = input.getterType;
		step = input.step;
		placeConversion = input.placeConversion;
		setterConversion = input.setterConversion;
		setterDeclaration = input.setterDeclaration;
		setterSources = input.setterSources.copy();
		setterCall = input.setterCall;
		if (setterSources.length == 0
			|| setterSources[setterSources.length - 1] != query.setterInputSource
			|| setterCall.getDeclaration() != setterDeclaration
			|| setterCall.getExpectedArguments().length != setterSources.length)
			throw "indexed update plan lost its selected setter call";
	}
}
