/**
	A stored structural value may contain additional fields. A fresh object literal
	uses its expected record shape, so extra literal fields are a source error.
	Keep this source rule separate from the shared member compatibility proof.
 */
function literalFits(expression:HxExpr, expected:TyType):Bool {
	final target = TyAliasExpansion.revealNonNullable(expected);
	if (!target.isAnonymous() || target.getAnonymousFieldNames().length == 0)
		return true;
	return switch expression {
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): literalFits(inner, expected);
		case EAnon(names, values):
			final fields = target.getAnonymousFieldNames();
			final types = target.getAnonymousFieldTypes();
			for (index in 0...names.length) {
				final selected = fields.indexOf(names[index]);
				if (selected < 0 || !literalFits(values[index], types[selected]))
					return false;
			}
			true;
		case _: true;
	};
}

/**
	Reuse the typed member relation for complete record/class operands in the
	caller's unchecked null policy. Nullable wrappers do not change the underlying
	field contract. Keep null literals and other categories with their normal checker.
	An abstract value is nominal: it reaches a record only through its declared
	`to` conversions, so its compatibility belongs to the conversion planner.
 */
function compatibility(index:TyperIndex, expected:TyType, actual:TyType, ?parameters:Array<TyTypeParameterId>):Null<TyCallArgumentCompatibility> {
	var target = TyAliasExpansion.revealNonNullable(expected);
	final source = TyAliasExpansion.revealNonNullable(actual);
	final sourceIdentity = source.getNominalIdentity();
	final generic = parameters != null && parameters.length > 0;
	// A record whose fields still hold open types (`{args: [], ret: null}` stored in a local)
	// unifies like upstream's monomorphs: each open component binds to the parameter's field
	// type (`FFun(func)` in upstream tests/unit UnitBuilder.hx, haxe_ocaml-u5s68).
	final openRecord = source.isAnonymous() && hasOpenComponent(source) && !generic;
	if (!target.isAnonymous()
		|| target.hasUnknownComponent()
		|| (source.hasUnknownComponent() && !openRecord)
		|| (!source.isAnonymous() && sourceIdentity == null)
		|| (sourceIdentity != null && index != null && index.getAbstractByFullName(sourceIdentity.getCanonicalName()) != null))
		return null;
	if (generic) {
		final inferred = TyMethodGenericBinding.structuralArgument(target, source, parameters, index);
		if (inferred == null)
			return Incompatible;
		target = inferred;
	}
	final solver = new TyInferenceSolver('structural-call-argument');
	final sourceTerm = openRecord ? openComponents(solver, source) : TyInferenceSolver.fromType(source);
	return TyStructuralConstraint.constrain(index, solver, sourceTerm, target) ? Compatible : Incompatible;
}

/** Whether `type` holds a component that `openComponents` opens: an unknown or a `null` literal. */
private function hasOpenComponent(type:TyType):Bool {
	if (type.isUnknown() || type.isNullLiteral())
		return true;
	if (type.isNullable())
		return hasOpenComponent(type.unwrapNull());
	if (type.isFunction())
		return type.getFunctionArguments().filter(hasOpenComponent).length > 0 || hasOpenComponent(type.getFunctionReturn());
	if (type.isAnonymous())
		return type.getAnonymousFieldTypes().filter(hasOpenComponent).length > 0;
	return type.getNominalIdentity() != null && type.getTypeArguments().filter(hasOpenComponent).length > 0;
}

/**
	`TyInferenceSolver.fromType`, except that each unknown component becomes a fresh variable of
	this private solver, so the proof can bind it without touching the caller's inference.
 */
private function openComponents(solver:TyInferenceSolver, type:TyType):TyInferenceTerm {
	if (type.isUnknown())
		return solver.fresh();
	// Upstream types a `null` field value as `Null<Unknown>`.
	if (type.isNullLiteral())
		return Nullable(solver.fresh());
	if (type.isNullable())
		return Nullable(openComponents(solver, type.unwrapNull()));
	if (type.isFunction())
		return Function(type.getFunctionArguments().map(argument -> openComponents(solver, argument)), openComponents(solver, type.getFunctionReturn()), type);
	if (type.isAnonymous())
		return Structure(type.getAnonymousFieldTypes().map(field -> openComponents(solver, field)), type);
	final identity = type.getNominalIdentity();
	return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(argument -> openComponents(solver, argument)));
}
