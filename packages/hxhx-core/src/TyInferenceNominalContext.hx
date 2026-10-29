import haxe.ds.StringMap;

/**
	Project an allocation's inference variables through its declared inheritance.
	The expected interface constrains the same variables as the concrete allocation;
	it must not replace that allocation with the interface or unify unrelated classes.
	Exact unification remains the solver's contract. The shared ancestor resolver owns
	binder substitution, graph validity, and rejection of conflicting inheritance.
 */
function view(index:TyperIndex, actual:TyInferenceTerm, expected:TyType):Null<TyInferenceTerm> {
	final target = expected.getNominalIdentity();
	return switch (actual) {
		case Nominal(identity, arguments) if (target != null && !identity.equals(target)):
			final provider = index == null ? null : index.getByFullName(identity.getCanonicalName());
			if (provider == null)
				return null;
			final parameters = TyNominalApplication.parameterIds(provider);
			if (parameters.length != arguments.length)
				return null;
			final ancestor = TyNominalAncestor.view(index, TyType.nominal(identity, parameters.map(TyType.typeParameter)), target);
			if (ancestor == null)
				return null;
			final bindings = new StringMap<TyInferenceTerm>();
			for (i in 0...parameters.length)
				bindings.set(parameters[i].getCanonicalKey(), arguments[i]);
			function term(type:TyType):TyInferenceTerm {
				final parameter = type.getTypeParameterIdentity();
				if (parameter != null && bindings.exists(parameter.getCanonicalKey()))
					return bindings.get(parameter.getCanonicalKey());
				if (type.isNullable())
					return Nullable(term(type.unwrapNull()));
				if (type.isFunction())
					return Function(type.getFunctionArguments().map(term), term(type.getFunctionReturn()), type);
				if (type.isAnonymous())
					return Structure(type.getAnonymousFieldTypes().map(term), type);
				final nominal = type.getNominalIdentity();
				return nominal == null ? Known(type) : Nominal(nominal, type.getTypeArguments().map(term));
			}
			term(ancestor);
		case _: actual;
	};
}
