/**
	Resolve extern indexing through the exact standard interface. Inherited edges
	substitute each declaration's own parameters before selecting the element.
	Abstract array-access operators are a separate contract.
 */
function element(index:TyperIndex, receiver:TyType):Null<TyType> {
	final actual = TyAliasExpansion.revealNonNullable(receiver);
	final contract = TyNominalAncestor.view(index, actual, new TyNominalTypeId("StdTypes.ArrayAccess"));
	if (contract == null)
		return null;
	final arguments = contract.getTypeArguments();
	return arguments.length == 1 ? arguments[0] : null;
}

/** Known classes need an array contract; abstracts and incomplete types have other owners. */
function isClass(index:TyperIndex, receiver:TyType):Bool {
	final actual = TyAliasExpansion.revealNonNullable(receiver);
	final identity = actual.getNominalIdentity();
	return identity != null && Std.isOfType(index.getByFullName(identity.getCanonicalName()), TyClassInfo);
}
