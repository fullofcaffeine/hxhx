/**
	View an applied class through one exact declared superclass or interface.
	Each edge substitutes its owner's binders before traversal. The result supplies
	generic argument evidence without changing the expression's concrete type.
	Missing declarations, malformed arity, cycles, and conflicting diamond routes
	cannot establish a usable ancestor. Abstract conversions are a separate owner.
 */
function view(index:TyperIndex, actual:TyType, expected:TyNominalTypeId):Null<TyType> {
	if (index == null || actual == null || expected == null)
		return null;
	var invalid = false;
	var selected:Null<TyType> = null;
	function visit(type:TyType, path:Array<String>):Void {
		final identity = type.getNominalIdentity();
		if (identity == null) {
			invalid = true;
			return;
		}
		final key = identity.getCanonicalName();
		if (path.indexOf(key) >= 0) {
			invalid = true;
			return;
		}
		final provider = index.getByFullName(key);
		if (provider == null || !Std.isOfType(provider, TyClassInfo)) {
			invalid = true;
			return;
		}
		// Only validated class/interface declarations own inheritance edges.
		final owner:TyClassInfo = cast provider;
		if (owner.getTypeParameterIds().length != type.getTypeArguments().length) {
			invalid = true;
			return;
		}
		if (identity.equals(expected)) {
			if (selected != null && selected.getSemanticKey() != type.getSemanticKey())
				invalid = true;
			selected = type;
			return;
		}
		final bindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), type.getTypeArguments(), key);
		final next = path.concat([key]);
		final parent = owner.getSuperType();
		if (parent != null)
			visit(TyTypeSubstitution.apply(parent, bindings), next);
		for (parent in owner.getInterfaceTypes())
			visit(TyTypeSubstitution.apply(parent, bindings), next);
	}
	visit(actual, []);
	return invalid ? null : selected;
}
