/**
	An empty anonymous bound requires an object-compatible type, not an arbitrary
	value. Classes and interfaces qualify; enum values and opaque abstracts do not.
	Declared abstract conversions can establish compatibility, but the underlying
	storage type alone cannot. This checks a generic bound without erasing the
	caller's inferred type or selecting a target representation.
 */
function accepts(type:TyType, index:TyperIndex):Bool {
	function visit(current:TyType, seen:Array<String>):Bool {
		if (current == null || current.hasUnknownComponent())
			return false;
		if (current.isNullable())
			return visit(current.unwrapNull(), seen);
		if (current.isAnonymous() || current.getSemanticKey() == "primitive:String")
			return true;
		// Array has this canonical bootstrap shape before its provider is loaded.
		if (current.isUnresolved())
			return current.getUnresolvedPath() == "Array" && current.getTypeArguments().length == 1;
		final identity = current.getNominalIdentity();
		if (identity == null || index == null)
			return false;
		final name = identity.getCanonicalName();
		// Runtime class values are selected as Class<T> by TypedRuntimeTypeTarget.
		if (name == "Class" && current.getTypeArguments().length == 1)
			return true;
		final owner = index.getByFullName(name);
		if (owner == null || owner.getIsEnum())
			return false;
		final abstractType = index.getAbstractByFullName(name);
		if (abstractType == null)
			return true;
		final key = current.getSemanticKey();
		if (seen.indexOf(key) >= 0 || abstractType.getTypeParameterIds().length != current.getTypeArguments().length)
			return false;
		final next = seen.concat([key]);
		final bindings = TyTypeSubstitution.bind(abstractType.getTypeParameterIds(), current.getTypeArguments(), name);
		for (conversion in abstractType.getImplicitToTypes())
			if (visit(TyTypeSubstitution.apply(conversion, bindings), next))
				return true;
		return false;
	}
	return visit(type, []);
}
