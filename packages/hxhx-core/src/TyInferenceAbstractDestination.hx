/**
	A written abstract destination can constrain an unfinished source value through
	its declared input headers. Keep the source's own inference variables and try
	headers in declaration order. Each attempt owns a fork, and the existing
	conversion planner must prove that the selected route preserves representation.
	A Dynamic input records a deferred fallback, so later concrete uses still win.
 */
function constrain(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType):Bool {
	final identity = expected.getNominalIdentity();
	final owner = identity == null || index == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
	if (owner == null || owner.getTypeParameterIds().length != expected.getTypeArguments().length)
		return false;
	final bindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), expected.getTypeArguments(), identity.getCanonicalName());
	for (header in owner.getImplicitFromTypes()) {
		final candidate = solver.fork();
		final declared = TyTypeSubstitution.apply(header, bindings);
		if (declared.isDynamic()) {
			candidate.observeDynamicUse(actual, true);
		} else {
			final projected = TyInferenceNominalContext.view(index, actual, declared);
			if (projected == null
				|| !(declared.isAnonymous() ? TyStructuralConstraint.constrain(index, candidate, projected,
					declared) : TyStructuralConstraint.constrainNominalAssignment(index, candidate, projected, declared)))
				continue;
		}
		final source = candidate.previewDynamicUses(actual);
		if (source.hasUnknownComponent())
			continue;
		final conversion = TyImplicitConversionPlan.select(index, expected, source);
		if (conversion == null || !conversion.isRepresentationPreservingAbstractConversion())
			continue;
		solver.commit(candidate);
		return true;
	}
	return false;
}
