/**
	Find a retained receiver's implementation of a referenced instance member.
	The candidate must declare the same member in a resolved descendant of the
	selected declaration's owner. Unrelated classes with the same method name do
	not qualify. Constructors are not virtual members. This pass expands retention;
	it does not choose or execute the implementation of a particular runtime call.
**/
function implementsReference(candidate:TypedFunction, reference:TypedFunction, providers:haxe.ds.StringMap<TypedClass>):Bool {
	final method = candidate.getDeclaration();
	final selected = reference.getDeclaration();
	if (method == null
		|| selected == null
		|| method.getIsStatic()
		|| selected.getIsStatic()
		|| method.getSignature().getName() == "new"
		|| method.getSignature().getName() != selected.getSignature().getName())
		return false;
	final destination = selected.getOwner().getCanonicalName();
	final visited = new haxe.ds.StringMap<Bool>();
	function visit(identity:TyNominalTypeId):Bool {
		final key = identity.getCanonicalName();
		if (key == destination)
			return true;
		if (visited.exists(key))
			return false;
		visited.set(key, true);
		final owner = providers.get(key);
		if (owner == null)
			throw "feature dispatch has no exact ancestor provider: " + key;
		final parents = owner.getResolvedImplements().concat(owner.getResolvedInterfaceExtends());
		if (owner.getResolvedExtends() != null)
			parents.push(owner.getResolvedExtends());
		for (parent in parents) {
			final ancestor = parent.getNominalIdentity();
			if (ancestor == null)
				throw "feature dispatch requires resolved nominal ancestors";
			if (visit(ancestor))
				return true;
		}
		return false;
	}
	return visit(method.getOwner());
}
