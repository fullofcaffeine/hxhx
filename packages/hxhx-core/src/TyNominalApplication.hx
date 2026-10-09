/**
	Apply a receiver's exact nominal arguments to its declared member signature.
	For example, Box<String>.get returns String even though the declaration uses T.
	The original signature remains the declaration lookup key; this copy is only
	for argument checking and result typing.
 */
function signature(index:TyperIndex, owner:TyNominalInfo, receiver:TyType, member:TyFunSig):TyFunSig {
	final declaration = owner.declarationForSignature(member);
	final effective = declaration == null || index == null ? member : index.getMethodBodyResults().signature(declaration);
	final bindings = receiverBindings(index, owner, receiver);
	if (bindings == null)
		return effective;
	return new TyFunSig(effective.getName(), effective.getIsStatic(), effective.getArgNames(), [
		for (argument in effective.getArgs())
			TyTypeSubstitution.apply(argument, bindings)
	],
		effective.getArgOptional(), effective.getArgRest(), TyTypeSubstitution.apply(effective.getReturnType(), bindings), effective.getPos());
}

/** Bounds and signatures must substitute the same exact receiver and ancestor application. */
function applyType(index:TyperIndex, owner:TyNominalInfo, receiver:TyType, type:TyType):TyType {
	final bindings = receiverBindings(index, owner, receiver);
	return bindings == null ? type : TyTypeSubstitution.apply(type, bindings);
}

/**
	Apply an instance field through its declaring owner, preserving the shared declaration.
	A Child<String> may inherit Parent<Int, String>.right: the parent's binder
	must become String even when lookup began at the child. Static storage has
	no instance application and keeps its declaration type.
 */
function fieldType(index:TyperIndex, field:TyFieldInfo, receiver:TyType):TyType {
	final effective = index == null ? field.getType() : index.getFieldInitializerTypes().result(field);
	if (field.getIsStatic() || index == null)
		return effective;
	final owner = index.getByFullName(field.getOwner().getCanonicalName());
	return owner == null ? effective : applyType(index, owner, receiver, effective);
}

/** Shared signature checking and inline expansion use the same declaring-owner view of an applied receiver. */
function receiverBindings(index:TyperIndex, owner:TyNominalInfo, receiver:TyType):Null<haxe.ds.StringMap<TyType>> {
	final parameters = parameterIds(owner);
	if (receiver == null || parameters.length == 0)
		return null;
	final actual = TyAliasExpansion.revealNonNullable(receiver);
	final originalIdentity = actual.getNominalIdentity();
	final applied = originalIdentity != null
		&& originalIdentity.equals(owner.getIdentity()) ? actual : TyNominalAncestor.view(index, actual, owner.getIdentity());
	final identity = applied == null ? null : applied.getNominalIdentity();
	if (identity == null || applied.getTypeArguments().length != parameters.length)
		return null;
	return TyTypeSubstitution.bind(parameters, applied.getTypeArguments(), identity.getCanonicalName());
}

/**
	Find the nearest extern dynamic-member contract through applied superclasses.
	Each edge substitutes its exact owner binders. A child marker overrides its
	parent's marker, while declared fields and methods must be checked first.
	Missing providers, malformed applications, and cycles cannot supply a type.
 */
function dynamicMemberType(index:TyperIndex, receiver:TyType):Null<TyType> {
	if (index == null || receiver == null)
		return null;
	var current:Null<TyType> = receiver.unwrapNull();
	final visited = new Array<String>();
	while (current != null) {
		final identity = current.getNominalIdentity();
		if (identity == null || visited.indexOf(identity.getCanonicalName()) >= 0)
			return null;
		visited.push(identity.getCanonicalName());
		final provider = index.getByFullName(identity.getCanonicalName());
		if (!Std.isOfType(provider, TyClassInfo))
			return null;
		// Only a validated class declaration can own a superclass or member marker.
		final owner:TyClassInfo = cast provider;
		if (owner.getTypeParameterIds().length != current.getTypeArguments().length)
			return null;
		final bindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), current.getTypeArguments(), identity.getCanonicalName());
		final member = owner.getDynamicMemberType();
		if (member != null)
			return TyTypeSubstitution.apply(member, bindings);
		final parent = owner.getSuperType();
		current = parent == null ? null : TyTypeSubstitution.apply(parent, bindings);
	}
	return null;
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
