/** A selected member keeps its declaration identity and its applied value type. */
private typedef StructuralRetentionMember = {
	final type:TyType;
	final ?method:TypedFunction;
	final ?field:TyFieldInfo;
};

/**
	Keep class members exposed when an already typed value enters a record contract.
	For example, returning Answer as { function value():Int; } exposes Answer.value
	even though the later call has no nominal method declaration. Only the source
	value's class and resolved ancestors supply members. Unrelated classes with
	similar names never enter this lookup. This is dependency discovery, not another
	assignment checker; callers supply boundaries already accepted by shared typing.
 */
class TypedStructuralRetention {
	final providers:haxe.ds.StringMap<TypedClass>;
	final retainMethod:TypedFunction->Void;
	final retainField:TyFieldInfo->Void;
	final seen:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();

	public function new(providers:haxe.ds.StringMap<TypedClass>, retainMethod:TypedFunction->Void, retainField:TyFieldInfo->Void) {
		this.providers = providers;
		this.retainMethod = retainMethod;
		this.retainField = retainField;
	}

	/** Follow nested record, callable, and container views without changing either semantic type. */
	public function boundary(expected:Null<TyType>, actual:TyType):Void {
		if (expected == null || actual == null)
			return;
		expected = TyAliasExpansion.revealNonNullable(expected);
		actual = TyAliasExpansion.revealNonNullable(actual);
		if (expected.getSemanticKey() == actual.getSemanticKey())
			return;
		final key = CompilerCacheIdentity.encode([expected.getSemanticKey(), actual.getSemanticKey()]);
		if (seen.exists(key))
			return;
		seen.set(key, true);
		if (expected.isAnonymous()) {
			for (wanted in expected.getAnonymousFields()) {
				if (actual.isAnonymous()) {
					final supplied = TyStructuralFieldRead.resolve(actual, wanted.name);
					if (supplied != null)
						boundary(wanted.type, supplied);
				} else if (actual.getNominalIdentity() != null) {
					final supplied = member(actual, wanted.name, []);
					if (supplied == null) {
						if (!wanted.isOptional)
							throw "structural retention has no selected member: " + actual.getDisplay() + "." + wanted.name;
						continue;
					}
					if (supplied.method != null)
						retainMethod(supplied.method);
					if (supplied.field != null)
						retainField(supplied.field);
					boundary(wanted.type, supplied.type);
				}
			}
		} else if (expected.isFunction() && actual.isFunction()) {
			boundary(expected.getFunctionReturn(), actual.getFunctionReturn());
			final wanted = expected.getFunctionArguments();
			final supplied = actual.getFunctionArguments();
			if (wanted.length == supplied.length)
				for (index in 0...wanted.length)
					boundary(supplied[index], wanted[index]);
		} else if (expected.getNominalIdentity() != null
			&& actual.getNominalIdentity() != null
			&& expected.getNominalIdentity().equals(actual.getNominalIdentity())) {
			final wanted = expected.getTypeArguments();
			final supplied = actual.getTypeArguments();
			if (wanted.length == supplied.length)
				for (index in 0...wanted.length)
					boundary(wanted[index], supplied[index]);
		}
	}

	/** Resolve inherited members with the original receiver's substitutions and exact program-owned declarations. */
	function member(receiver:TyType, name:String, ancestors:Array<String>):Null<StructuralRetentionMember> {
		final identity = receiver.getNominalIdentity();
		if (identity == null || ancestors.indexOf(identity.getCanonicalName()) >= 0)
			return null;
		final owner = providers.get(identity.getCanonicalName());
		if (owner == null)
			throw "structural retention has no exact class provider: " + identity.getCanonicalName();
		final info = owner.getSemanticInfo();
		final bindings = TyTypeSubstitution.bind(TyNominalApplication.parameterIds(info), receiver.getTypeArguments(), identity.getCanonicalName());
		for (fn in owner.getFunctions()) {
			final declaration = fn.getDeclaration();
			if (!declaration.getIsStatic() && declaration.getIsPublic() && declaration.getSignature().getName() == name) {
				final signature = TyCallableSignature.fromDeclaration(declaration).getFunctionType();
				return {type: TyTypeSubstitution.apply(signature, bindings), method: fn};
			}
		}
		final field = info.fieldInfo(name);
		if (field != null && !field.getIsStatic() && field.getIsPublic())
			return {type: TyTypeSubstitution.apply(field.getType(), bindings), field: field};
		final parent = owner.getResolvedExtends();
		return parent == null ? null : member(TyTypeSubstitution.apply(parent, bindings), name, ancestors.concat([identity.getCanonicalName()]));
	}
}
