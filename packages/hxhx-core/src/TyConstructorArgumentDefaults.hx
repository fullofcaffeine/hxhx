/**
	The fallback for each type parameter of a constructed class, used only when nothing in the body
	gives it a type (haxe_ocaml-6a7w5).

	Upstream Haxe 4.3.7 keeps such a parameter as a monomorph (`new Foo()` is `Foo<Unknown<0>>`).
	hxhx needs a concrete type when it seals the function, so the parameter takes its declared
	bound: a single bound as written, an intersection of structures as one structure. Without a
	usable bound (none, one that names other type parameters, or nominal intersections) the entry
	is null and the solver uses Dynamic.
**/
final class TyConstructorArgumentDefaults {
	public static function bounds(index:Null<TyperIndex>, owner:Null<TyNominalInfo>):Array<Null<TyType>> {
		if (index == null || owner == null)
			return [];
		return [
			for (parameter in TyNominalApplication.parameterIds(owner))
				bound(index.getParameterBounds(parameter))
		];
	}

	static function bound(declared:Null<Array<TyType>>):Null<TyType> {
		if (declared == null || declared.length == 0)
			return null;
		for (type in declared)
			if (type.hasUnknownComponent() || TyTypeSubstitution.parameterIdentities(type).length > 0)
				return null;
		if (declared.length == 1)
			return declared[0];
		final fields = new Array<TyAnonymousField>();
		for (type in declared) {
			final structure = TyAliasExpansion.reveal(type);
			if (!structure.isAnonymous())
				return null;
			for (field in structure.getAnonymousFields()) {
				final existing = Lambda.find(fields, other -> other.name == field.name);
				if (existing == null)
					fields.push(field);
				else if (existing.type.getSemanticKey() != field.type.getSemanticKey())
					return null;
			}
		}
		return TyType.declaredAnonymous(fields);
	}
}
