/**
	Select the nearest declared constructor and retain its applied owner facts.

	Owner arguments specialize the candidate signature before ordinary call scoring.
	The application retains the original declaration, so specialization cannot
	invent a new constructor identity. Missing providers and tied or
	inapplicable candidates remain unresolved for a later diagnostic/publication boundary.
 */
function select(index:TyperIndex, constructed:TyType, arguments:Array<TyType>, sources:Array<HxExpr>,
		score:(TyFunSig, Array<TyType>, Array<TyTypeParameterId>) -> Int):Null<TypedConstructorApplication> {
	if (index == null || constructed == null || constructed.getNominalIdentity() == null)
		return null;
	final path = TypedConstructorPath.select(index, constructed);
	if (path == null)
		return null;
	final owner = path.getOwner();
	final appliedOwner = path.getOwnerType();
	final identity = appliedOwner.getNominalIdentity();
	// The nominal index has distinct concrete declaration kinds. Narrow only at
	// this boundary, after runtime validation, to obtain their exact owner binders.
	final parameters = if (Std.isOfType(owner, TyAbstractInfo)) {
		(cast owner : TyAbstractInfo).getTypeParameterIds();
	} else if (Std.isOfType(owner, TyClassInfo)) {
		(cast owner : TyClassInfo).getTypeParameterIds();
	} else {
		return null;
	}
	if (parameters.length != appliedOwner.getTypeArguments().length)
		return null;
	final substitutions = TyTypeSubstitution.bind(parameters, appliedOwner.getTypeArguments(), identity.getCanonicalName());
	var bestScore = -1;
	var best:Null<TyDeclarationInfo> = null;
	var tied = false;
	for (signature in owner.instanceMethodCandidates("new")) {
		final declaration = owner.declarationForSignature(signature);
		if (declaration == null || declaration.getIsStatic() || !declaration.getOwner().equals(identity))
			continue;
		final applied = new TyFunSig(signature.getName(), false, signature.getArgNames(), [
			for (argument in signature.getArgs())
				TyTypeSubstitution.apply(argument, substitutions)
		],
			signature.getArgOptional(), signature.getArgRest(), TyTypeSubstitution.apply(signature.getReturnType(), substitutions), signature.getPos());
		final alignment = TyCallbackArgumentContext.align(TyCallableSignature.fromDeclaration(declaration, applied), sources, arguments, index);
		final ranked = new Array<TyType>();
		switch alignment {
			case Rejected(_):
				continue;
			case Aligned(slots):
				for (slot in slots)
					switch slot {
						case Omitted: ranked.push(TyType.fromHintText("Null"));
						case Supplied(source): ranked.push(arguments[source]);
						case RestElements(sources): for (source in sources)
								ranked.push(arguments[source]);
						case RestSpread(source): ranked.push(arguments[source]);
					}
		}
		// Ranking sees parameter positions after shared optional selection. These
		// null type facts score omissions; they never become executable operands.
		final candidateScore = score(applied, ranked, TyMethodGenericBinding.inferableTypeParameters(declaration));
		if (candidateScore < 0)
			continue;
		if (candidateScore > bestScore) {
			bestScore = candidateScore;
			best = declaration;
			tied = false;
		} else if (candidateScore == bestScore) {
			tied = true;
		}
	}
	return tied
		|| best == null ? null : new TypedConstructorApplication(owner, best, constructed, {index: index, arguments: sources, types: arguments}, path);
}
