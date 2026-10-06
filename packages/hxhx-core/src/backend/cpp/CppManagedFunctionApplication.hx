package backend.cpp;

/**
	An immutable application of owner arguments to one exact function declaration.
	An interface application describes call transport, not an executable body.
	Source declarations and local identities remain unchanged. Native storage must
	resolve their types through this view, so separate Int and String applications
	cannot share a representation chosen from an unapplied type parameter.
	Only the program's validated constructor and method owners can create the view.
 */
class CppManagedFunctionApplication {
	public final projection:TypedBackendFunctionProjection;
	public final receiverType:TyType;
	public final backingType:Null<TyType>;

	/** Constructor cells retain the declaration's generic null independently of its semantic backing. */
	public final storedBackingType:Null<TyType>;

	public final identity:String;

	final bindings:haxe.ds.StringMap<TyType>;
	final validate:Void->Void;
	final forwardedTypes:Array<TyType>;
	final casts:CppManagedCastPlan;

	@:allow(backend.cpp.CppManagedClassStorage)
	@:allow(backend.cpp.CppManagedMethods)
	private function new(input:{
		projection:TypedBackendFunctionProjection,
		receiverType:TyType,
		parameters:Array<TyTypeParameterId>,
		backingType:Null<TyType>,
		casts:CppManagedCastPlan,
		?forwardedTypes:Array<TyType>,
		validate:Void->Void
	}) {
		projection = input.projection;
		receiverType = input.receiverType;
		casts = input.casts;
		forwardedTypes = input.forwardedTypes == null ? [] : input.forwardedTypes.copy();
		validate = input.validate;
		validate();
		bindings = TyTypeSubstitution.bind(input.parameters, receiverType.getTypeArguments(), projection.getStableIdentity());
		for (argument in receiverType.getTypeArguments()) {
			CppManagedClosureAbi.assertComplete(argument);
			if (TyTypeSubstitution.parameterIdentities(argument).length != 0)
				throw "managed function application requires concrete owner arguments";
		}
		backingType = input.backingType == null ? null : resolveType(input.backingType);
		storedBackingType = input.backingType == null ? null : resolveStorageType(input.backingType);
		identity = CompilerCacheIdentity.encode([
			"managed-function-application-v2",
			projection.getStableIdentity(),
			projection.getBodyRevision(),
			receiverType.getSemanticKey(),
			CompilerCacheIdentity.encode([for (type in forwardedTypes) type.getSemanticKey()])
		]);
	}

	/** Constructor-free child classes execute their fields before this authored ancestor body. */
	public function getForwardedTypes():Array<TyType> {
		assertCurrent();
		return forwardedTypes.copy();
	}

	/** Recheck exact program ownership and the unchanged source before reusing a plan. */
	public function assertCurrent():Void {
		validate();
		projection.requireCaptureCatalog().assertCurrent();
	}

	/** Substitute structural types by exact binder identity, never by display spelling. */
	public function resolveType(type:TyType):TyType {
		assertCurrent();
		final selected = TyTypeSubstitution.apply(type, bindings);
		CppManagedClosureAbi.assertComplete(selected);
		if (TyTypeSubstitution.parameterIdentities(selected).length != 0)
			throw "managed function application retains an unapplied type parameter";
		return selected;
	}

	public function parameterTypes():Array<TyType>
		return [
			for (parameter in projection.getParameters())
				resolveType(parameter.getBinding().getType())
		];

	public function resultType():TyType
		return resolveType(projection.getReturnType());

	/**
		Preserve null in ordinary class values declared as T, including method
		parameters, locals, and results. Semantic owner arguments stay concrete:
		Box<T> keeps its semantic Int argument; scalar-backed generic abstracts add
		a nullable storage view without changing that argument or shared typing.
	 */
	public function resolveStorageType(type:TyType):TyType
		return CppManagedAppliedStorage.resolve(type, resolveType, casts);

	public function storedResultType():TyType
		return resolveStorageType(projection.getReturnType());
}
