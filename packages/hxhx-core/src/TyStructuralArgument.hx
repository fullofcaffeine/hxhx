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
 */
function compatibility(index:TyperIndex, expected:TyType, actual:TyType):Null<TyCallArgumentCompatibility> {
	final target = TyAliasExpansion.revealNonNullable(expected);
	final source = TyAliasExpansion.revealNonNullable(actual);
	if (!target.isAnonymous()
		|| target.hasUnknownComponent()
		|| source.hasUnknownComponent()
		|| (!source.isAnonymous() && source.getNominalIdentity() == null))
		return null;
	final solver = new TyInferenceSolver('structural-call-argument');
	return TyStructuralConstraint.constrain(index, solver, TyInferenceSolver.fromType(source), target) ? Compatible : Incompatible;
}
