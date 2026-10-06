package backend.cpp;

/**
	Apply a declaring class's arguments to one exact field initializer. Constructors
	select when this field executes; the field retains its own source, captures,
	and type binders. No constructor projection substitutes for field ownership.
	Only class storage can create this view after checking program membership.
 */
class CppManagedInitializerApplication {
	public final projection:TypedBackendFieldInitializerProjection;
	public final ownerType:TyType;
	public final identity:String;

	final bindings:haxe.ds.StringMap<TyType>;
	final validate:Void->Void;
	final casts:CppManagedCastPlan;

	@:allow(backend.cpp.CppManagedClassStorage)
	function new(input:{
		projection:TypedBackendFieldInitializerProjection,
		ownerType:TyType,
		parameters:Array<TyTypeParameterId>,
		casts:CppManagedCastPlan,
		validate:Void->Void
	}) {
		projection = input.projection;
		ownerType = input.ownerType;
		casts = input.casts;
		validate = input.validate;
		validate();
		bindings = TyTypeSubstitution.bind(input.parameters, ownerType.getTypeArguments(), projection.getStableIdentity());
		CppManagedClosureAbi.assertComplete(ownerType);
		if (TyTypeSubstitution.parameterIdentities(ownerType).length != 0)
			throw "managed initializer application requires concrete owner arguments";
		identity = CompilerCacheIdentity.encode([
			"managed-initializer-application-v1",
			projection.getStableIdentity(),
			projection.getBodyRevision(),
			ownerType.getSemanticKey()
		]);
	}

	/** Reuse requires the same program field and unchanged authored and projected bodies. */
	public function assertCurrent():Void {
		validate();
		projection.requireCaptureCatalog().assertCurrent();
	}

	/** Bind by semantic parameter identity while leaving shared initializer facts unchanged. */
	public function resolveType(type:TyType):TyType {
		assertCurrent();
		final selected = TyTypeSubstitution.apply(type, bindings);
		CppManagedClosureAbi.assertComplete(selected);
		if (TyTypeSubstitution.parameterIdentities(selected).length != 0)
			throw "managed initializer application retains an unapplied type parameter";
		return selected;
	}

	/** Ordinary generic fields and their closures use the same null-preserving storage rule as methods. */
	public function resolveStorageType(type:TyType):TyType
		return CppManagedAppliedStorage.resolve(type, resolveType, casts);
}
