/**
	Infer an open parameter through an actual abstract's declared `to` headers.

	What
	- `new Wrap(native)` where `Wrap<T>` takes `Raw<T>` and `native:Nat<Int>` is an
	  abstract declared `to Raw<T>` binds `T = Int`, as Haxe does. Exact
	  unification alone cannot see through the abstract, so the constructor had no
	  applicable declaration.

	How
	- Each `to` header is applied to the actual abstract's arguments and tried in
	  its own solver transaction, in declaration order. The existing conversion
	  planner must then prove that the inferred destination is a
	  representation-preserving `to` conversion of the actual value. Headers that
	  infer different destinations are ambiguous and constrain nothing.
	- This is the output-side companion of `TyInferenceAbstractInput`, which reads
	  an expected abstract's `from` headers. Neither infers permission from an
	  abstract's backing type alone.
 */
function constrain(input:{
	solver:TyInferenceSolver,
	expected:TyType,
	actual:TyType,
	term:TyType->TyInferenceTerm,
	index:TyperIndex
}):Bool {
	final identity = input.actual.getNominalIdentity();
	final info = identity == null || input.index == null ? null : input.index.getAbstractByFullName(identity.getCanonicalName());
	if (info == null || info.getTypeParameterIds().length != input.actual.getTypeArguments().length)
		return false;
	final bindings = TyTypeSubstitution.bind(info.getTypeParameterIds(), input.actual.getTypeArguments(), identity.getCanonicalName());
	var selected:Null<TyInferenceSolver> = null;
	var selectedKey:Null<String> = null;
	for (header in info.getImplicitToTypes()) {
		final candidate = input.solver.fork();
		final declared = TyTypeSubstitution.apply(header, bindings);
		if (!candidate.constrain(input.term(input.expected), TyInferenceSolver.fromType(declared)))
			continue;
		final inferred = candidate.preview(input.term(input.expected));
		if (inferred.hasUnknownComponent())
			continue;
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
