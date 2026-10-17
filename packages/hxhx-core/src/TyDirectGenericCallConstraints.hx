/** Inputs belong to an isolated candidate for an already selected declaration. */
typedef TyDirectGenericCallConstraintInput = {
	final solver:TyInferenceSolver;
	final callable:TyInferenceTerm;
	final signature:TyFunSig;
	final order:TyMethodArgumentOrder;
	final arguments:Array<HxExpr>;
	final terms:Array<Null<TyInferenceTerm>>;
	final index:TyperIndex;
	final accepts:(TyType, TyType) -> Bool;
}

/**
	Connect nested call results to the selected outer call's parameter variables.
	Selection already owns conversions and the source-to-parameter mapping. This pass
	adds equations only for incomplete terms; it never reselects an overload or
	replaces a complete compatible argument with its parameter type.
 */
function constrain(input:TyDirectGenericCallConstraintInput):Bool {
	final parameters = switch input.callable {
		case Function(arguments, _, _): arguments;
		case _: throw "direct call constraints require a callable term";
	};
	if (input.arguments.length != input.terms.length || parameters.length != input.signature.getArgs().length)
		throw "direct call constraint inputs differ from the selected signature";
	final rest = input.signature.getArgRest();
	for (source in 0...input.arguments.length) {
		var actual = input.terms[source];
		if (actual == null)
			continue;
		final parameter = input.order.parameterIndex(source);
		var expected = parameters[parameter];
		final spread = input.arguments[source].match(ECall(EIdent("__hxhx_spread"), [_]));
		if (parameter < rest.length && rest[parameter]) {
			// The canonical callable carries rest element types, while its source
			// declaration still describes the array visible inside the method body.
			if (spread) {
				actual = element(actual);
				if (actual == null)
					return false;
			}
		} else if (spread) {
			return false;
		}
		final wanted = input.solver.preview(expected);
		final supplied = input.solver.preview(actual);
		if (supplied.isDynamic()) {
			// Explicit Dynamic supplies no concrete constraint, but a parameter
			// used only this way must publish Dynamic after later uses are solved.
			input.solver.observeDynamicUse(expected);
			continue;
		}
		if (wanted.isDynamic()) {
			input.solver.observeDynamicUse(actual);
			continue;
		}
		if (supplied.isNullLiteral())
			continue;
		if (!wanted.hasUnknownComponent() && !supplied.hasUnknownComponent()) {
			if (!input.accepts(wanted, supplied))
				return false;
			continue;
		}
		final projected = TyInferenceNominalContext.view(input.index, actual, wanted);
		if (projected == null || !TyStructuralConstraint.constrainTerms(input.index, input.solver, projected, expected))
			return false;
	}
	return true;
}

/** Rest declarations store an Array in their bodies; spread operands retain Array or Rest element identities. */
private function element(term:TyInferenceTerm):Null<TyInferenceTerm> {
	return switch term {
		case Nominal(identity, [value])
			if (identity.getCanonicalName() == "Array"
				|| identity.getCanonicalName() == "haxe.Array"
				|| identity.getCanonicalName() == "haxe.Rest"): value;
		case _: null;
	};
}
