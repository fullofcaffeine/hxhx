/**
	Apply a receiver's exact nominal arguments to its declared member signature.
	For example, Box<String>.get returns String even though the declaration uses T.
	The original signature remains the declaration lookup key; this copy is only
	for argument checking and result typing.
 */
function signature(index:TyperIndex, owner:TyNominalInfo, receiver:TyType, member:TyFunSig):TyFunSig {
	final bindings = receiverBindings(index, owner, receiver);
	if (bindings == null)
		return member;
	return new TyFunSig(member.getName(), member.getIsStatic(), member.getArgNames(),
		[for (argument in member.getArgs()) TyTypeSubstitution.apply(argument, bindings)], member.getArgOptional(), member.getArgRest(),
		TyTypeSubstitution.apply(member.getReturnType(), bindings), member.getPos());
}

/** Bounds and signatures must substitute the same exact receiver and ancestor application. */
function applyType(index:TyperIndex, owner:TyNominalInfo, receiver:TyType, type:TyType):TyType {
	final bindings = receiverBindings(index, owner, receiver);
	return bindings == null ? type : TyTypeSubstitution.apply(type, bindings);
}

private function receiverBindings(index:TyperIndex, owner:TyNominalInfo, receiver:TyType):Null<haxe.ds.StringMap<TyType>> {
	final parameters = parameterIds(owner);
	if (receiver == null || parameters.length == 0)
		return null;
	final actual = receiver.unwrapNull();
	final originalIdentity = actual.getNominalIdentity();
	final applied = originalIdentity != null
		&& originalIdentity.equals(owner.getIdentity()) ? actual : TyNominalAncestor.view(index, actual, owner.getIdentity());
	final identity = applied == null ? null : applied.getNominalIdentity();
	if (identity == null || applied.getTypeArguments().length != parameters.length)
		return null;
	return TyTypeSubstitution.bind(parameters, applied.getTypeArguments(), identity.getCanonicalName());
}

/** Nominal providers expose owner binders through their validated declaration kind. */
function parameterIds(owner:TyNominalInfo):Array<TyTypeParameterId> {
	// The index contains distinct declaration kinds. Narrow only after checking
	// the provider kind; no spelling or target representation is binding evidence.
	if (Std.isOfType(owner, TyClassInfo))
		return (cast owner : TyClassInfo).getTypeParameterIds();
	if (Std.isOfType(owner, TyAbstractInfo))
		return (cast owner : TyAbstractInfo).getTypeParameterIds();
	return [];
}
