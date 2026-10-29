import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/**
	Checked view of one nullable abstract getter value inside one indexed update.

	Why: `Map<String, MapCounter>.get` returns `Null<MapCounter>`. Upstream Haxe still
	types `counters["x"]++` as an Int-storage step on that value, and `counters["x"] += 2`
	as a call to `MapCounter.compound` with the raw nullable value as its first
	argument. Neither case inserts a runtime conversion. This fact lets the indexed
	selector see the applied owner `MapCounter` for lookup while every actual type
	remains the original `Null<MapCounter>`.

	What it retains:
	- the update query and its getter occurrence (`query.getterSource`);
	- the getter's original inference term and complete original nullable type;
	- the applied nominal type found under a finite `Null<...>` envelope, its abstract
	  declaration, and the applied storage type (exact `Int` only in this slice).

	What it is not: a general `Null<A> -> A` conversion, a runtime unwrap, or permission
	for the right-hand operand, another update, or a computed setter input. Float
	storage, unresolved applications, type parameters and nested abstract storage
	are not selected and keep their existing diagnostics.

	How: `select` is called once by `TyIndexedUpdateOperation` after the getter has
	been typed in the candidate scope. `validate` is repeated by every consumer and
	rejects a changed query, getter term, getter type, owner or storage proof.
 */
class TyIndexedNullableAbstractOperand {
	public final query:TyIndexedUpdateQuery;
	public final originalType:TyType;
	public final applied:TyType;
	public final owner:TyAbstractInfo;
	public final storage:TyType;

	final term:TyInferenceTerm;
	final index:TyperIndex;

	function new(input:{
		query:TyIndexedUpdateQuery,
		originalType:TyType,
		applied:TyType,
		owner:TyAbstractInfo,
		storage:TyType,
		term:TyInferenceTerm,
		index:TyperIndex
	}) {
		query = input.query;
		originalType = input.originalType;
		applied = input.applied;
		owner = input.owner;
		storage = input.storage;
		term = input.term;
		index = input.index;
	}

	/** Strip only real `Null<...>` wrappers; aliases have already been resolved by the getter type. */
	static function stripNullable(type:TyType):TyType {
		var value = type;
		while (value.isNullable())
			value = value.getNullableInner();
		return value;
	}

	/**
		Return the checked view for a complete `Null<A>` getter whose applied abstract `A`
		has exact `Int` storage, or null when the getter is outside this bounded case.
	 */
	@:allow(TyIndexedUpdateOperation)
	static function select(query:TyIndexedUpdateQuery, type:TyType, environment:TyFunctionEnv, index:TyperIndex):Null<TyIndexedNullableAbstractOperand> {
		if (query == null
			|| type == null
			|| index == null
			|| !type.isNullable()
			|| type.hasUnknownComponent()
			|| type.isUnresolved()
			|| TyTypeSubstitution.parameterIdentities(type).length != 0)
			return null;
		final applied = stripNullable(type);
		final identity = applied.getNominalIdentity();
		final owner = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		if (owner == null)
			return null;
		final storage = TyNominalApplication.applyType(index, owner, applied, owner.getUnderlyingType());
		if (storage == null || storage.getSemanticKey() != "primitive:Int")
			return null;
		final term = environment.getInference().sourceTerm(query.getterSource, environment);
		if (term == null)
			throw "indexed nullable abstract getter has no retained term";
		final result = new TyIndexedNullableAbstractOperand({
			query: query,
			originalType: type,
			applied: applied,
			owner: owner,
			storage: storage,
			term: term,
			index: index
		});
		result.validate(environment);
		return result;
	}

	/** Lookup and admission preserve the original source term, applied owner and storage proof. */
	public function validate(environment:TyFunctionEnv, ?retainedInference:TyFunctionInference):Void {
		query.validate(environment.getOwnerIdentity());
		final inference = retainedInference == null ? environment.getInference() : retainedInference;
		if (inference.sourceTerm(query.getterSource, environment) != term
			|| inference.expressionType(query.getterSource, originalType, environment).getSemanticKey() != originalType.getSemanticKey()
			|| !originalType.isNullable()
			|| stripNullable(originalType).getSemanticKey() != applied.getSemanticKey()
			|| applied.getNominalIdentity() != owner.getIdentity()
			|| storage.getSemanticKey() != "primitive:Int"
			|| TyNominalApplication.applyType(index, owner, applied, owner.getUnderlyingType()).getSemanticKey() != storage.getSemanticKey())
			throw "indexed nullable abstract operand changed its source, term or applied owner";
	}

	/**
		True only for this getter's exact original actual type and the exact applied
		abstract as expected parameter. A different abstract with the same `Int`
		storage, or another application of the same abstract, is not admitted.
	 */
	public function admits(expected:TyType, actual:TyType):Bool
		return expected != null
			&& actual != null
			&& expected.getSemanticKey() == applied.getSemanticKey()
			&& actual.getSemanticKey() == originalType.getSemanticKey();
}
