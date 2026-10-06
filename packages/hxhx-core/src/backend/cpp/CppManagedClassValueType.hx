package backend.cpp;

/**
	Class<T> stores a nullable runtime descriptor, not an abstract backing value.
	The shared runtime-type resolver reserves canonical Class as a language core
	identity. Package and secondary declarations with that short name remain
	different nominal identities. Require the current program's exact declaration
	and parameter shape before selecting storage; this does not admit reflection,
	instance allocation, or arbitrary conversions between Class arguments.
 */
function selects(program:CppTypedProgramProjection, type:TyType):Bool {
	CppManagedClosureAbi.assertComplete(type);
	final identity = type.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Class")
		return false;
	program.assertCurrent();
	final facts = program.requireClass(program.requireClassIdentity(identity.getCanonicalName())).requireSemanticFacts();
	if (type.getTypeArguments().length != 1 || facts.getTypeParameterIds().length != 1)
		throw "managed class handle requires the exact Class type parameter";
	switch facts.getNominalKind() {
		case AbstractValue(_):
			return true;
		case _:
			throw "managed class handle requires the core abstract declaration";
	}
}

/** Return the erased Array descriptor's element parameter only after checking both core declarations. */
function arrayElement(program:CppTypedProgramProjection, type:TyType):Null<TyType> {
	if (!selects(program, type))
		return null;
	final instance = type.getTypeArguments()[0];
	final identity = instance.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != 'Array')
		return null;
	final facts = program.requireClass(program.requireClassIdentity('Array')).requireSemanticFacts();
	if (instance.getTypeArguments().length != 1 || facts.getTypeParameterIds().length != 1)
		throw 'managed Array class value requires its exact element parameter';
	switch facts.getNominalKind() {
		case ClassInstance:
			return instance.getTypeArguments()[0];
		case _:
			throw 'managed Array class value requires its core class declaration';
	}
}

/** Widen a stored Array class handle; this never permits narrowing a stored erased handle. */
function permitsArrayErasure(program:CppTypedProgramProjection, target:TyType, source:TyType):Bool {
	final element = arrayElement(program, target);
	return element != null && element.isDynamic() && arrayElement(program, source) != null;
}
