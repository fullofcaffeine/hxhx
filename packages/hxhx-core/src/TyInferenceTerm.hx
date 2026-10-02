/**
	A temporary constraint term. Variables belong to one inference owner and never
	enter immutable typed bodies; the solver publishes ordinary TyType snapshots.
 */
enum TyInferenceTerm {
	Known(type:TyType);
	Variable(identity:TyInferenceVariable);
	Nominal(identity:TyNominalTypeId, arguments:Array<TyInferenceTerm>);
	Nullable(inner:TyInferenceTerm);
	Function(arguments:Array<TyInferenceTerm>, result:TyInferenceTerm);
}

/** Identity is object-owned, so unrelated solvers cannot forge equal variables by name. */
@:allow(TyInferenceSolver)
class TyInferenceVariable {
	public final owner:String;
	public final ordinal:Int;
	public final openMethodParameter:Null<TyOpenMethodParameterId>;

	function new(owner:String, ordinal:Int, ?openMethodParameter:TyOpenMethodParameterId) {
		this.owner = owner;
		this.ordinal = ordinal;
		this.openMethodParameter = openMethodParameter;
	}
}
