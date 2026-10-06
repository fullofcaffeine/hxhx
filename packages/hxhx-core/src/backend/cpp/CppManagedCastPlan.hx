package backend.cpp;

/**
	Plan value-preserving casts and class upcasts through exact program types.
	Admit an authored unchecked cast only when exact storage types agree; an exact
	null literal may also retain null in a destination with null-capable storage.
	An explicit cast does not need an abstract's implicit conversion header. It
	still needs a target operation: this plan supports preserving a stored value,
	and rejects casts requiring a runtime check or a representation change.
	The enclosing program checks source revisions before and after emission.
 */
class CppManagedCastPlan {
	final program:CppTypedProgramProjection;
	final owners:haxe.ds.StringMap<HxExpr->Null<TypedBackendCastOccurrence>> = new haxe.ds.StringMap();

	public function new(program:CppTypedProgramProjection) {
		this.program = program;
		program.assertCurrent();
		for (module in program.getModules())
			for (owner in module.projection.getClasses()) {
				for (method in owner.getFunctions())
					owners.set(method.getStableIdentity(), method.findCast);
				for (initializer in owner.getFieldInitializers())
					owners.set(initializer.getStableIdentity(), initializer.findCast);
			}
	}

	/** Equal owner names cannot authorize a cast object projected from another program. */
	public function requireStoredValue(occurrence:TypedBackendCastOccurrence):Void {
		final find = owners.get(occurrence.getOwnerIdentity());
		if (find == null || find(occurrence.getExpression()) != occurrence)
			throw "managed cast belongs to another program";
		// Both a valid annotation and a checked reference cast preserve an exact
		// null literal. This does not guess which syntax was written or authorize
		// non-null checked casts; scalar backing types still need conversion.
		if (occurrence.getSourceType().isNullLiteral() && retainsNull(occurrence.getTargetType()))
			return;
		if (!occurrence.isUnchecked())
			throw "managed cast requires an explicit runtime conversion plan";
		final source = storageType(occurrence.getSourceType(), new haxe.ds.StringMap());
		final target = storageType(occurrence.getTargetType(), new haxe.ds.StringMap());
		if (source.getSemanticKey() != target.getSemanticKey())
			throw "managed cast requires an explicit runtime conversion plan";
	}

	/** Return exact substituted storage facts without changing values or erasing container arguments. */
	public function representationType(type:TyType):TyType {
		program.assertCurrent();
		return storageType(type, new haxe.ds.StringMap());
	}

	/**
		A generic abstract backed by T retains null until a concrete destination
		requests Int or Bool storage. Keep the abstract identity in this target-only
		view: Box<T> applied to Int uses Null<Box<Int>>, while written Box<Int>
		uses Box<Int>. Ordinary classes and reference backing types are unchanged.
	 */
	public function appliedAbstractStorage(declared:TyType, applied:TyType):TyType {
		if (applied.getNominalIdentity() == null)
			return applied;
		if (declared.isTypeParameter()) {
			final concrete = representationType(applied);
			return concrete.getSemanticKey() == "primitive:Int"
				|| concrete.getSemanticKey() == "primitive:Bool" ? TyType.nullable(applied) : applied;
		}
		if (declared.getNominalIdentity() == null)
			return applied;
		if (!declared.getNominalIdentity().equals(applied.getNominalIdentity()))
			throw "managed abstract storage requires the same declared owner";
		if (TyTypeSubstitution.parameterIdentities(declared).length == 0)
			return applied;
		final generic = storageType(declared, new haxe.ds.StringMap());
		if (!generic.isTypeParameter())
			return applied;
		final concrete = representationType(applied);
		return concrete.getSemanticKey() == "primitive:Int"
			|| concrete.getSemanticKey() == "primitive:Bool" ? TyType.nullable(applied) : applied;
	}

	/** Array class-handle widening copies one descriptor; it does not convert array elements. */
	public function permitsArrayClassErasure(target:TyType, source:TyType):Bool {
		return CppManagedClassValueType.permitsArrayErasure(program, target, source);
	}

	/** An upcast keeps one instance; each ancestor must match after substituting all inherited type arguments. */
	public function permitsClassUpcast(target:TyType, source:TyType):Bool {
		if (target.getNominalIdentity() == null || source.getNominalIdentity() == null)
			return false;
		program.assertCurrent();
		final sourceName = source.getNominalIdentity().getCanonicalName();
		final targetName = target.getNominalIdentity().getCanonicalName();
		final graph = program.getClassGraph();
		final sourceNode = graph.findNode(sourceName);
		final targetNode = graph.findNode(targetName);
		if (sourceNode == null || targetNode == null)
			return false;
		for (view in graph.requireAppliedAssignableTypes(source))
			if (view.getSemanticKey() == target.getSemanticKey())
				return true;
		return false;
	}

	/** Resolve abstract backing storage before allowing null, without introducing a scalar default. */
	public function retainsNull(type:TyType):Bool {
		program.assertCurrent();
		final stored = storageType(type, new haxe.ds.StringMap());
		return stored.isNullLiteral()
			|| stored.isDynamic()
			|| stored.isNullable()
			|| stored.isAnonymous()
			|| stored.isFunction()
			|| stored.getSemanticKey() == 'primitive:String'
			|| stored.getNominalIdentity() != null;
	}

	/** Substitute declaration-bound type arguments at every abstract layer; never erase container arguments. */
	function storageType(type:TyType, visiting:haxe.ds.StringMap<Bool>):TyType {
		CppManagedClosureAbi.assertComplete(type);
		if (type.getNullableInner() != null)
			return TyType.nullable(storageType(type.getNullableInner(), visiting));
		if (CppManagedClassValueType.selects(program, type))
			return type;
		final identity = type.getNominalIdentity();
		if (identity == null)
			return type;
		final name = identity.getCanonicalName();
		final facts = program.requireClass(program.requireClassIdentity(name)).requireSemanticFacts();
		return switch facts.getNominalKind() {
			case AbstractValue(underlying):
				if (visiting.exists(name))
					throw "managed cast contains a cyclic abstract representation";
				visiting.set(name, true);
				final bindings = TyTypeSubstitution.bind(facts.getTypeParameterIds(), type.getTypeArguments(), name);
				final result = storageType(TyTypeSubstitution.apply(underlying, bindings), visiting);
				visiting.remove(name);
				result;
			case ClassInstance | EnumValue: type;
		};
	}
}
