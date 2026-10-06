/**
	Whether a parameter can carry null without a target-specific scalar conversion.
	This is method-selection evidence, not permission to bypass null-safety checks.
	Abstracts follow their declared underlying type with exact generic substitution.
	A class type parameter remains a generic carrier while its body is checked;
	accepting null there neither instantiates the parameter nor supplies type evidence.
	Unresolved user types remain unsupported; the bootstrap typer already models the
	standard Array constructor structurally before its standard-library module loads.
 */
function acceptsLiteral(type:TyType, index:TyperIndex):Bool {
	var current = type;
	final visited = new Array<String>();
	while (current != null) {
		if (current.isNullable()
			|| current.isDynamic()
			|| current.isTypeParameter()
			|| current.isFunction()
			|| current.isAnonymous()
			|| current.getSemanticKey() == TyType.fromHintText("String").getSemanticKey())
			return true;
		if (current.isUnresolved())
			return current.getUnresolvedPath() == "Array" && current.getTypeArguments().length == 1;
		final identity = current.getNominalIdentity();
		if (identity == null || index == null)
			return false;
		final name = identity.getCanonicalName();
		if (visited.indexOf(name) >= 0)
			return false;
		visited.push(name);
		final abstractType = index.getAbstractByFullName(name);
		if (abstractType == null)
			return index.getByFullName(name) != null;
		final parameters = abstractType.getTypeParameterIds();
		final arguments = current.getTypeArguments();
		if (parameters.length != arguments.length)
			return false;
		current = TyTypeSubstitution.apply(abstractType.getUnderlyingType(), TyTypeSubstitution.bind(parameters, arguments, name));
	}
	return false;
}
