import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/** A candidate owns inference facts while helper selection over its queries is incomplete. */
@:allow(TyFunctionInference)
@:allow(TyFunctionEnv)
class TyIndexedUpdateTrial {
	final parent:TyFunctionInference;
	final parentUnchanged:() -> Bool;
	var committed:Bool = false;
	final environmentsUnchanged:Array<() -> Bool> = [];

	public final candidate:TyFunctionInference;
	public final query:TyIndexedUpdateQuery;

	function new(parent:TyFunctionInference, candidate:TyFunctionInference, query:TyIndexedUpdateQuery, parentUnchanged:() -> Bool) {
		this.parent = parent;
		this.candidate = candidate;
		this.query = query;
		this.parentUnchanged = parentUnchanged;
	}
}
