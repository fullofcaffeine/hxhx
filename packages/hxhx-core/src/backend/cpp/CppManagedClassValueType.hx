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
	type = descriptorView(program, type);
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

/**
	Validate the shared generic declaration before selecting its erased descriptor
	storage. This view never replaces the semantic source type and cannot grant a
	stored erased handle the scheme's independently contextual uses.
 */
private function descriptorView(program:CppTypedProgramProjection, type:TyType):TyType {
	final scheme = type.getClassValueScheme();
	if (scheme == null)
		return type;
	program.assertCurrent();
	final facts = program.requireClass(program.requireClassIdentity(scheme.getIdentity().getCanonicalName())).requireSemanticFacts();
	final parameters = facts.getTypeParameterIds();
	final selected = scheme.getParameters();
	if (!facts.getNominalKind().match(ClassInstance) || parameters.length != selected.length)
		throw "managed class scheme differs from its current declaration";
	for (index in 0...parameters.length)
		if (parameters[index].getCanonicalKey() != selected[index].getCanonicalKey())
			throw "managed class scheme differs from its current declaration";
	return scheme.application(parameters.map(_ -> TyType.fromHintText("Dynamic")));
}

/** Return the erased Array descriptor's element parameter only after checking both core declarations. */
function arrayElement(program:CppTypedProgramProjection, type:TyType):Null<TyType> {
	if (!selects(program, type))
		return null;
	final instance = descriptorView(program, type).getTypeArguments()[0];
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
	if (target.getClassValueScheme() != null)
		return false;
	final element = arrayElement(program, target);
	return element != null && element.isDynamic() && arrayElement(program, source) != null;
}

/** Only an existing shared scheme can acquire a contextual Class<T> view, never the reverse. */
function permitsSchemeContext(program:CppTypedProgramProjection, target:TyType, source:TyType):Bool {
	final scheme = source.getClassValueScheme();
	return scheme != null && selects(program, source) && selects(program, target) && scheme.accepts(target);
}

/** Check a fresh ordinary class literal without requesting physical instance storage. */
function acceptsNominalLiteral(program:CppTypedProgramProjection, identity:TyNominalTypeId, target:TyType):Bool {
	if (!selects(program, target))
		return false;
	final instance = descriptorView(program, target).getTypeArguments()[0];
	if (instance.getNominalIdentity() == null || instance.getNominalIdentity().getCanonicalName() != identity.getCanonicalName())
		return false;
	final owner = program.requireClass(program.requireClassIdentity(identity.getCanonicalName()));
	final facts = owner.requireSemanticFacts();
	if (!facts.getNominalKind().match(ClassInstance))
		return false;
	if (instance.getTypeArguments().length != facts.getTypeParameterIds().length)
		throw 'managed class literal requires exact type argument arity';
	if (TyTypeSubstitution.parameterIdentities(instance).length != 0)
		throw 'managed class literal requires complete applied arguments';
	for (metadata in HxClassDecl.getMetadata(owner.getDeclaration())) {
		final raw = StringTools.trim(metadata);
		final name = StringTools.startsWith(raw, '@:') ? raw.substr(2) : StringTools.startsWith(raw, ':') ? raw.substr(1) : raw;
		if (name == 'generic' || StringTools.startsWith(name, 'generic('))
			throw 'managed specialized classes require their own runtime identity plan';
	}
	return true;
}
