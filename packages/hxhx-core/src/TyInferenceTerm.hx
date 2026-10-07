/**
	A temporary constraint term. Variables belong to one inference owner and never
	enter immutable typed bodies; the solver publishes ordinary TyType snapshots.
 */
enum TyInferenceTerm {
	Known(type:TyType);
	Variable(identity:TyInferenceVariable);
	Nominal(identity:TyNominalTypeId, arguments:Array<TyInferenceTerm>);
	Nullable(inner:TyInferenceTerm);

	/** The immutable source type retains parameter names and omission/rest rules while child terms are solved. */
	Function(arguments:Array<TyInferenceTerm>, result:TyInferenceTerm, signature:TyType);

	/** Sorted field terms retain the original access, optionality, and method-binder contracts. */
	Structure(fields:Array<TyInferenceTerm>, signature:TyType);
}

/** Distinguish missing input annotations from operation results that can acquire a Dynamic carrier. */
enum TyInferenceVariableKind {
	Required;
	OmittedInput;
	UntypedResult;
}

/** Identity is object-owned, so unrelated solvers cannot forge equal variables by name. */
@:allow(TyInferenceSolver)
class TyInferenceVariable {
	public final owner:String;
	public final ordinal:Int;
	public final openMethodParameter:Null<TyOpenMethodParameterId>;

	/** Omitted inputs, explicitly untyped results, and their projections may retain missing evidence. */
	public final allowsUnknown:Bool;

	public final kind:TyInferenceVariableKind;

	function new(owner:String, ordinal:Int, ?openMethodParameter:TyOpenMethodParameterId, kind:TyInferenceVariableKind = Required) {
		this.owner = owner;
		this.ordinal = ordinal;
		this.openMethodParameter = openMethodParameter;
		this.allowsUnknown = kind != Required;
		this.kind = kind;
	}
}
