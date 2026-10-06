import haxe.ds.StringMap;

/** Assignment direction is distinct from the solver's exact unification relation. */
private enum StructuralDirection {
	Output;
	Input;
	Exact;
}

/**
	Constrain a class value against a structural contract on a caller-owned fork.
	Member lookup uses declared owners and applied superclass types. The original
	allocation term remains nominal; its member views share the same variables.
	The caller commits only after every required member succeeds.
**/
function constrain(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType):Bool {
	return value(index, solver, actual, expected, Output);
}

/** Exact binding discharges earlier field reads against real class members, without replacing the nominal identity with a record. */
function constrainExact(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType):Bool {
	return constrainTerms(index, solver, actual, TyInferenceSolver.fromType(expected));
}

/**
	Accept an inferred Box<Array<T>> at Box<Dynamic> without erasing its Array shape.
	A fresh variable for each Dynamic destination receives the original argument shape. Its Dynamic
	fallback applies only to remaining solver-owned holes at seal, so later concrete
	evidence still wins. Other arguments keep exact unification, including numeric
	arguments and reverse Dynamic assignments. Failed assignments discard every
	new variable and fallback together with their speculative bindings.
 */
function constrainNominalAssignment(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType):Bool {
	if (expected.getNominalIdentity() == null)
		return constrainExact(index, solver, actual, expected);
	final candidate = solver.fork();
	function context(type:TyType):TyInferenceTerm {
		if (type.isDynamic()) {
			final destination = candidate.fresh();
			candidate.observeDynamicUse(destination);
			return destination;
		}
		final identity = type.getNominalIdentity();
		return identity == null ? TyInferenceSolver.fromType(type) : Nominal(identity, type.getTypeArguments().map(context));
	}
	if (!constrainTerms(index, candidate, actual, context(expected)))
		return false;
	solver.commit(candidate);
	return true;
}

/** Link existing inference terms while checking any nominal member requirements against their declarations. */
function constrainTerms(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyInferenceTerm):Bool {
	return solver.constrain(actual, expected, (receiver, name) -> inferredMember(index, receiver, name));
}

/** Project declared member types through the receiver's existing variables, including inherited owner substitutions. */
private function inferredMember(index:TyperIndex, receiver:TyInferenceTerm, name:String):Null<TyInferenceTerm> {
	if (index == null)
		return null;
	return switch receiver {
		case Nominal(identity, arguments):
			final owner = index.getByFullName(identity.getCanonicalName());
			if (owner == null)
				return null;
			final parameters = TyNominalApplication.parameterIds(owner);
			if (parameters.length != arguments.length)
				return null;
			final supplied = member(index, TyType.nominal(identity, parameters.map(TyType.typeParameter)), name, []);
			if (supplied == null)
				return null;
			switch supplied.kind {
				case Variable(_, getter, _) if (getter == "never" || getter == "null"): return null;
				case Method(binders) if (binders.length != 0): return null;
				case _:
			}
			final bindings = new StringMap<TyInferenceTerm>();
			for (i in 0...parameters.length)
				bindings.set(parameters[i].getCanonicalKey(), arguments[i]);
			term(supplied.type, bindings);
		case _: null;
	};
}

private function value(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType, direction:StructuralDirection):Bool {
	if (expected.isAnonymous() && direction != Input) {
		return switch actual {
			case Nominal(identity, arguments):
				final owner = index.getByFullName(identity.getCanonicalName());
				if (owner == null)
					return false;
				final parameters = TyNominalApplication.parameterIds(owner);
				if (parameters.length != arguments.length)
					return false;
				final symbolic = TyType.nominal(identity, parameters.map(TyType.typeParameter));
				final bindings = new StringMap<TyInferenceTerm>();
				for (i in 0...parameters.length)
					bindings.set(parameters[i].getCanonicalKey(), arguments[i]);
				for (wanted in expected.getAnonymousFields()) {
					final supplied = member(index, symbolic, wanted.name, []);
					if (supplied == null
						|| !memberRules(wanted, supplied)
						|| !value(index, solver, term(supplied.type, bindings), wanted.type, memberDirection(wanted)))
						return false;
				}
				true;
			case Structure(fields, signature):
				final supplied = signature.getAnonymousFields();
				for (wanted in expected.getAnonymousFields()) {
					var found = -1;
					for (i in 0...supplied.length)
						if (supplied[i].name == wanted.name)
							found = i;
					if (found < 0) {
						if (wanted.isOptional)
							continue;
						return false;
					}
					if (!memberRules(wanted, supplied[found])
						|| !value(index, solver, fields[found], wanted.type, memberDirection(wanted)))
						return false;
				}
				true;
			case _: constrainExact(index, solver, actual, expected);
		};
	}
	if (expected.isFunction())
		switch actual {
			case Function(arguments, result, signature):
				final wanted = expected.getFunctionParameters();
				final supplied = signature.getFunctionParameters();
				if (wanted.length != supplied.length)
					return false;
				for (i in 0...wanted.length) {
					if (wanted[i].isRest != supplied[i].isRest || (wanted[i].isOptional && !supplied[i].isOptional))
						return false;
					final argumentDirection = direction == Exact || wanted[i].isRest ? Exact : direction == Output ? Input : Output;
					if (!value(index, solver, arguments[i], wanted[i].type, argumentDirection))
						return false;
				}
				return expected.getFunctionReturn().isVoid()
					&& direction == Output
					|| value(index, solver, result, expected.getFunctionReturn(), direction);
			case _:
		}
	final concrete = solver.preview(actual);
	if (!concrete.hasUnknownComponent()) {
		if (direction == Exact)
			return concrete.getSemanticKey() == expected.getSemanticKey();
		final compatibility = direction == Output ? TyAssignmentCompatibility.classify(expected, concrete,
			Unchecked) : TyAssignmentCompatibility.classify(concrete, expected, Unchecked);
		if (compatibility != Unknown)
			return compatibility == Compatible;
		// Callback inputs reverse nominal assignment as well as primitive
		// assignment: a function accepting Base can serve a Child caller.
		if (direction == Input && !expected.hasUnknownComponent())
			return value(index, solver, TyInferenceSolver.fromType(expected), concrete, Output);
	}
	final projected = direction == Input ? actual : TyInferenceNominalContext.view(index, actual, expected);
	return projected != null && constrainExact(index, solver, projected, expected);
}

/** Mutable fields require exact value types; methods and read-only fields provide output values. */
private function memberDirection(field:TyAnonymousField):StructuralDirection {
	return switch field.kind {
		case Method(_): Output;
		case Variable(finalField, _, setter): finalField || setter == "never" || setter == "null" ? Output : Exact;
	};
}

private function access(mode:String):String
	return mode.length == 0 ? "default" : mode;

/** A writable function field is not a method, and nominal optional fields still require a real member. */
private function memberRules(wanted:TyAnonymousField, supplied:TyAnonymousField):Bool {
	if (supplied.visibility != Public)
		return false;
	return switch [wanted.kind, supplied.kind] {
		case [Method(first), Method(second)]: first.length == 0 && second.length == 0;
		case [
			Variable(wantedFinal, wantedGet, wantedSet),
			Variable(suppliedFinal, suppliedGet, suppliedSet)
		]: access(wantedGet) == access(suppliedGet) && (wantedFinal
			|| wantedSet == "never"
			|| wantedSet == "null"
			|| !suppliedFinal
			&& access(wantedSet) == access(suppliedSet));
		case _: false;
	};
}

/** Resolve and substitute one real member; inherited class binders remain tied to the original receiver. */
private function member(index:TyperIndex, receiver:TyType, name:String, seen:Array<String>):Null<TyAnonymousField> {
	final identity = receiver.getNominalIdentity();
	if (identity == null || seen.indexOf(identity.getCanonicalName()) >= 0)
		return null;
	final provider = index.getByFullName(identity.getCanonicalName());
	// Only class declarations own these superclass and instance-member contracts.
	if (provider == null || !Std.isOfType(provider, TyClassInfo))
		return null;
	final owner:TyClassInfo = cast provider;
	if (owner.getTypeParameterIds().length != receiver.getTypeArguments().length)
		return null;
	final bindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), receiver.getTypeArguments(), owner.getFullName());
	final methods = owner.instanceMethodCandidates(name);
	if (methods.length > 0) {
		if (methods.length != 1 || name == "new")
			return null;
		final declaration = owner.declarationForSignature(methods[0]);
		if (declaration == null || !declaration.getIsPublic())
			return null;
		final signature = index.getMethodBodyResults().signature(declaration);
		final effective = TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType();
		return {
			name: name,
			type: TyTypeSubstitution.apply(effective, bindings),
			kind: Method(declaration.getTypeParameterIds()),
			isOptional: false,
			visibility: Public,
			metadata: declaration.getMetadata(),
			position: declaration.getPosition()
		};
	}
	final field = owner.fieldInfo(name);
	if (field != null) {
		if (field.getIsStatic() || !field.getIsPublic())
			return null;
		return {
			name: name,
			type: TyTypeSubstitution.apply(index.getFieldInitializerTypes().result(field), bindings),
			kind: Variable(field.getIsFinal(), field.getPropertyGet(), field.getPropertySet()),
			isOptional: false,
			visibility: Public,
			metadata: [],
			position: HxPos.unknown()
		};
	}
	final parent = owner.getSuperType();
	return parent == null ? null : member(index, TyTypeSubstitution.apply(parent, bindings), name, seen.concat([owner.getFullName()]));
}

/** Substitute owner variables through nested records and callables without materializing unsolved values. */
private function term(type:TyType, bindings:StringMap<TyInferenceTerm>):TyInferenceTerm {
	final parameter = type.getTypeParameterIdentity();
	if (parameter != null && bindings.exists(parameter.getCanonicalKey()))
		return bindings.get(parameter.getCanonicalKey());
	if (type.isNullable())
		return Nullable(term(type.unwrapNull(), bindings));
	if (type.isFunction())
		return Function(type.getFunctionArguments().map(child -> term(child, bindings)), term(type.getFunctionReturn(), bindings), type);
	if (type.isAnonymous())
		return Structure(type.getAnonymousFieldTypes().map(child -> term(child, bindings)), type);
	final identity = type.getNominalIdentity();
	return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(child -> term(child, bindings)));
}
