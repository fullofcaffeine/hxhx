import haxe.ds.StringMap;

/** Project declared types through existing inference variables without allocating or solving them. */
function apply(type:TyType, bindings:StringMap<TyInferenceTerm>):TyInferenceTerm {
	final parameter = type.getTypeParameterIdentity();
	if (parameter != null && bindings.exists(parameter.getCanonicalKey()))
		return bindings.get(parameter.getCanonicalKey());
	if (type.isNullable())
		return Nullable(apply(type.unwrapNull(), bindings));
	if (type.isFunction())
		return Function(type.getFunctionArguments().map(child -> apply(child, bindings)), apply(type.getFunctionReturn(), bindings), type);
	if (type.isAnonymous())
		return Structure(type.getAnonymousFieldTypes().map(child -> apply(child, bindings)), type);
	final identity = type.getNominalIdentity();
	return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(child -> apply(child, bindings)));
}
