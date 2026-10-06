/**
	Select the standard extension provider from resolved enum receiver facts.
	The caller loads that provider through its request-owned module loader and
	uses ordinary declaration selection after explicit using directives. This
	module supplies no method names, signatures, or executable implementations.
 */
function providerPath(index:TyperIndex, receiver:TyType):Null<String> {
	return findProvider(index, receiver, []);
}

/** Repeated bounds do not turn an unresolved parameter cycle into an enum fact. */
private function findProvider(index:TyperIndex, receiver:TyType, seen:Array<String>):Null<String> {
	if (index == null || receiver == null)
		return null;
	final type = receiver.unwrapNull();
	final key = type.getSemanticKey();
	if (seen.indexOf(key) >= 0)
		return null;
	seen.push(key);
	if (type.isTypeParameter()) {
		for (bound in index.getParameterBounds(type.getTypeParameterIdentity())) {
			final provider = findProvider(index, bound, seen);
			if (provider != null)
				return provider;
		}
		return null;
	}
	final identity = type.getNominalIdentity();
	if (identity == null)
		return null;
	final name = identity.getCanonicalName();
	if (name == "Enum" && type.getTypeArguments().length == 1)
		return "haxe.EnumTools";
	final declaration = index.getByFullName(name);
	return declaration != null
		&& (declaration.getIsEnum()
			|| (name == "EnumValue" && index.getAbstractByFullName(name) != null)) ? "haxe.EnumTools.EnumValueTools" : null;
}
