/**
	Infer through an explicitly declared abstract input without weakening exact unification.
	Each header attempt owns a transaction. The existing conversion planner must then
	prove that the inferred application accepts the actual stored value unchanged.
	This never infers permission from an abstract's backing type alone.
 */
function constrain(input:{
	solver:TyInferenceSolver,
	expected:TyType,
	actual:TyType,
	term:TyType->TyInferenceTerm,
	index:TyperIndex
}):Bool {
	final identity = input.expected.getNominalIdentity();
	final info = identity == null || input.index == null ? null : input.index.getAbstractByFullName(identity.getCanonicalName());
	if (info == null || info.getTypeParameterIds().length != input.expected.getTypeArguments().length)
		return false;
	final bindings = TyTypeSubstitution.bind(info.getTypeParameterIds(), input.expected.getTypeArguments(), identity.getCanonicalName());
	var selected:Null<TyInferenceSolver> = null;
	var selectedKey:Null<String> = null;
	for (header in info.getImplicitFromTypes()) {
		final candidate = input.solver.fork();
		final declared = TyTypeSubstitution.apply(header, bindings);
		if (!candidate.constrain(input.term(declared), TyInferenceSolver.fromType(input.actual)))
			continue;
		final inferred = candidate.preview(input.term(input.expected));
		final conversion = TyImplicitConversionPlan.select(input.index, inferred, input.actual);
		if (conversion == null || !conversion.isRepresentationPreservingAbstractConversion())
			continue;
		final key = inferred.getSemanticKey();
		if (selected != null && selectedKey != key)
			return false;
		selected = candidate;
		selectedKey = key;
	}
	if (selected == null)
		return false;
	input.solver.commit(selected);
	return true;
}
