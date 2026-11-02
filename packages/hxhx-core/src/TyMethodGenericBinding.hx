/**
	Infers the bounded, unconstrained method-generic relationships that shared
	call typing can currently prove.

	Method parameters are bound from semantic argument types, including public
	structural members and nested nominal and function shapes. Indexed superclass and interface substitutions
	let a derived argument constrain the corresponding base-type parameters
	without changing the argument's own type. A conflicting binding makes the candidate
	inapplicable. A parameter that is still open in the selected return type
	produces `Unknown` instead of escaping into a caller-local type hint where a
	backend could mistake it for an unrelated class.

	Constrained parameters use declaration-resolved semantic bounds. Call selection
	must validate those bounds before accepting a candidate. Target carriers and
	rendered type names are never binding evidence.
**/
class TyMethodGenericBinding {
	static function parameterIdentity(type:TyType, methodTypeParameters:Array<TyTypeParameterId>):Null<TyTypeParameterId> {
		if (type == null || !type.isTypeParameter() || methodTypeParameters == null)
			return null;
		final identity = type.getTypeParameterIdentity();
		if (identity == null)
			return null;
		for (parameter in methodTypeParameters)
			if (parameter.equals(identity))
				return parameter;
		return null;
	}

	/** Return parameters with representable bounds; candidate selection still proves their constraints. **/
	public static function inferableTypeParameters(declaration:Null<TyDeclarationInfo>):Array<TyTypeParameterId> {
		if (declaration == null)
			return [];
		final constraints = declaration.getResolvedTypeParameterConstraints();
		return declaration.getTypeParameterIds().filter(parameter -> {
			final bounds = constraints.get(parameter.getCanonicalKey());
			if (bounds != null)
				for (bound in bounds)
					if (bound.hasUnknownComponent() || bound.isUnresolved())
						return false;
			return true;
		});
	}

	/**
		Validate inferred direct-call arguments against bounds resolved at their declaration, never caller spellings.

		A bound can name another method parameter, as in `Std.downcast<T:{}, S:T>(value:T, c:Class<S>)`.
		Upstream Haxe types such a parameter as a monomorph (an inference variable). When the
		arguments do not fix it, the dependent check `S:T` binds it instead of failing:

		- Dynamic or an unchecked `cast null` leaves `T` open, so `S:T` closes `T` to `S` and
		  `T`'s own bounds are then checked against that type. `Std.downcast(dynamicValue, Sub)`
		  closes `T` to `Sub` and passes `T:{}`; `pick<T:String, S:T>(dynamicValue, 5)` closes
		  `T` to `Int` and fails on `pick.T`.
		- A `null` literal makes `T` a nullable monomorph whose own bounds upstream has already
		  accepted, so a bound that still names only such parameters passes. Both
		  `Std.downcast(null, Sub)` and `pick(null, 5)` are accepted.
	**/
	public static function constraintFailure(declaration:TyDeclarationInfo, signature:TyFunSig, actual:Array<TyType>, applyBound:TyType->TyType,
			accepts:(TyType, TyType) -> Bool, index:TyperIndex):Null<String> {
		final constraints = declaration.getResolvedTypeParameterConstraints();
		final parameters = declaration.getTypeParameterIds();
		final found = bindings(signature, actual, actual.length, inferableTypeParameters(declaration), index);
		// Conflicting evidence binds nothing; each bound then depends on its own arguments.
		final inferred:haxe.ds.StringMap<TyType> = found == null ? new haxe.ds.StringMap<TyType>() : found;
		if (found != null)
			closeFromDependentBounds(declaration, signature, actual, applyBound, inferred, index);
		final nullOpen = parameters.filter(parameter -> !inferred.exists(parameter.getCanonicalKey())
			&& evidence(signature, actual, parameter).match(NullOnly));
		for (parameter in parameters) {
			final key = parameter.getCanonicalKey();
			if (!constraints.exists(key))
				continue;
			final supplied = inferred.get(key);
			for (constraint in constraints.get(key)) {
				final bound = applyBound(constraint);
				if (bound.hasUnknownComponent() || bound.isUnresolved())
					return failure(signature, parameter);
				if (supplied == null) {
					if (evidence(signature, actual, parameter).match(Constraining))
						return failure(signature, parameter);
				} else if (!hasUnbound(bound, nullOpen, inferred) && !accepts(substitute(bound, parameters, inferred), supplied))
					return failure(signature, parameter);
			}
		}
		return null;
	}

	static function failure(signature:TyFunSig, parameter:TyTypeParameterId):String
		return "Constraint check failure for " + signature.getName() + "." + parameter.getName();

	/**
		Bind each method parameter left open by Dynamic or an unchecked cast from the bounds that name it, in place.

		A parameter with no argument, with unresolved evidence, or with a `null` literal is not
		closed here; `constraintFailure` handles those cases. A newly closed parameter can close
		a further one (`U:T, T:S`), so repeat until no binding changes. Each repeated pass has
		bound at least one more parameter, so the loop runs at most once per parameter.
	**/
	static function closeFromDependentBounds(declaration:TyDeclarationInfo, signature:TyFunSig, actual:Array<TyType>, applyBound:TyType->TyType,
			inferred:haxe.ds.StringMap<TyType>, index:TyperIndex):Void {
		final constraints = declaration.getResolvedTypeParameterConstraints();
		final parameters = declaration.getTypeParameterIds();
		var changed = true;
		while (changed) {
			changed = false;
			final open = parameters.filter(parameter -> !inferred.exists(parameter.getCanonicalKey())
				&& evidence(signature, actual, parameter).match(DynamicOnly));
			if (open.length == 0)
				return;
			for (parameter in parameters) {
				final supplied = inferred.get(parameter.getCanonicalKey());
				final bounds = constraints.get(parameter.getCanonicalKey());
				if (supplied == null || bounds == null)
					continue;
				for (constraint in bounds) {
					final bound = applyBound(constraint);
					if (!hasUnbound(bound, open, inferred))
						continue;
					final closed = new haxe.ds.StringMap<TyType>();
					// A conflict adds nothing; the ordinary bound check reports it.
					if (!collect(bound, supplied, open, closed, index))
						continue;
					for (key in closed.keys())
						if (!inferred.exists(key)) {
							inferred.set(key, closed.get(key));
							changed = true;
						}
				}
			}
		}
	}

	/**
		Classify the arguments that reach an unbound method parameter.

		Null and explicit Dynamic leave method variables open; unresolved types, or no argument
		at all, do not authorize a bound. Any `null` literal makes the parameter `NullOnly`.
	**/
	static function evidence(signature:TyFunSig, actual:Array<TyType>, parameter:TyTypeParameterId):TyParameterEvidence {
		function contains(type:TyType):Bool {
			final identity = type.getTypeParameterIdentity();
			if (identity != null && identity.equals(parameter))
				return true;
			if (type.isNullable())
				return contains(type.unwrapNull());
			for (child in type.getTypeArguments().concat(type.getFunctionArguments()))
				if (contains(child))
					return true;
			return type.isFunction() && contains(type.getFunctionReturn());
		}
		var found = false;
		var sawNull = false;
		final expected = signature.getArgs();
		for (index in 0...actual.length)
			if (index < expected.length && contains(expected[index])) {
				if (actual[index].isNullLiteral())
					sawNull = true;
				else if (!actual[index].isDynamic())
					return Constraining;
				found = true;
			}
		return !found ? Constraining : sawNull ? NullOnly : DynamicOnly;
	}

	/** Whether this exact semantic type is one of the inferable method parameters. **/
	public static function isInferableParameter(type:TyType, methodTypeParameters:Array<TyTypeParameterId>):Bool {
		return parameterIdentity(type, methodTypeParameters) != null;
	}

	/** Compare the semantic constructors around nested generic arguments. **/
	public static function sameTypeConstructor(left:TyType, right:TyType):Bool {
		if (left == null || right == null)
			return false;
		if (left.isAbstractMeta() || right.isAbstractMeta())
			return left.isAbstractMeta() && right.isAbstractMeta();
		final leftIdentity = left.getNominalIdentity();
		final rightIdentity = right.getNominalIdentity();
		if (leftIdentity != null || rightIdentity != null)
			return leftIdentity != null && rightIdentity != null && leftIdentity.getCanonicalName() == rightIdentity.getCanonicalName();
		return left.isUnresolved() && right.isUnresolved() && left.getUnresolvedPath() == right.getUnresolvedPath();
	}

	/**
		Gather evidence in a candidate-owned map. A recursive visit can stop discovery,
		but callers must still prove the complete substituted structural contract.
	 */
	static function collect(expected:TyType, actual:TyType, methodTypeParameters:Array<TyTypeParameterId>, bindings:haxe.ds.StringMap<TyType>,
			index:TyperIndex, selectedSignature:Bool = false, ?activeAliases:Array<String>):Bool {
		if (expected == null || actual == null || methodTypeParameters.length == 0)
			return true;
		if (activeAliases == null)
			activeAliases = [];
		final alias = expected.getAliasDefinition();
		if (alias != null) {
			// Revisit a recursive definition when new bindings can expose another
			// parameter, as in Link<A,B,C> whose next field is Link<B,C,A>.
			// An unchanged set ends discovery, never the complete compatibility proof.
			final sourceAlias = actual.getAliasDefinition();
			final owner = actual.getNominalIdentity();
			final key = alias.getDeclaration().getCanonicalName()
				+ "|"
				+ (sourceAlias != null ? sourceAlias.getDeclaration().getCanonicalName() : owner != null ? owner.getCanonicalName() : actual.getSemanticKey())
				+ "|"
				+ methodTypeParameters.filter(parameter -> !bindings.exists(parameter.getCanonicalKey()))
					.map(parameter -> parameter.getCanonicalKey())
					.join(";");
			if (activeAliases.indexOf(key) >= 0)
				return true;
			activeAliases = activeAliases.concat([key]);
		}
		expected = TyAliasExpansion.reveal(expected);
		actual = TyAliasExpansion.reveal(actual);
		final scheme = actual.getClassValueScheme();
		final context = expected.unwrapNull().getNominalIdentity();
		if (scheme != null && context != null && context.getCanonicalName() == "Class")
			return collect(expected, scheme.preview(), methodTypeParameters, bindings, index, selectedSignature, activeAliases);
		// Null carries no concrete type evidence, even for a bare T parameter.
		// Candidate legality is checked separately by overload selection.
		if (actual.isNullLiteral())
			return true;
		final parameter = parameterIdentity(expected, methodTypeParameters);
		if (parameter != null) {
			if (actual.isUnknown() || (actual.isDynamic() && !selectedSignature))
				return true;
			final parameterKey = parameter.getCanonicalKey();
			final previous = bindings.get(parameterKey);
			if (previous == null) {
				bindings.set(parameterKey, actual);
				return true;
			}
			if (selectedSignature)
				return previous.getSemanticKey() == actual.getSemanticKey();
			final unified = TyType.unify(previous, actual);
			if (unified == null)
				return false;
			bindings.set(parameterKey, unified);
			return true;
		}
		if (expected.isNullable() || actual.isNullable())
			return collect(expected.unwrapNull(), actual.unwrapNull(), methodTypeParameters, bindings, index, selectedSignature, activeAliases);
		if (expected.isAnonymous() && methodTypeParameters.length > 0) {
			final fields = expected.getAnonymousFields();
			// Payloads must contribute evidence before a recursive edge can stop.
			fields.sort((left, right) -> {
				final a = TyAliasExpansion.containsApplication(left.type);
				final b = TyAliasExpansion.containsApplication(right.type);
				return a != b ? (a ? 1 : -1) : left.name < right.name ? -1 : left.name > right.name ? 1 : 0;
			});
			for (field in fields) {
				final supplied = TyStructuralConstraint.argumentMember(index, actual, field);
				if (supplied != null
					&& !collect(field.type, supplied, methodTypeParameters, bindings, index, selectedSignature, activeAliases))
					return false;
			}
			return true;
		}
		if (expected.isFunction() || actual.isFunction()) {
			if (!expected.isFunction() || !actual.isFunction())
				return true;
			final expectedArguments = expected.getFunctionArguments();
			final actualArguments = actual.getFunctionArguments();
			if (expectedArguments.length != actualArguments.length)
				return true;
			for (argumentIndex in 0...expectedArguments.length)
				if (!collect(expectedArguments[argumentIndex], actualArguments[argumentIndex], methodTypeParameters, bindings, index, selectedSignature,
					activeAliases))
					return false;
			final expectedReturn = expected.getFunctionReturn();
			final actualReturn = actual.getFunctionReturn();
			return expectedReturn == null
				|| actualReturn == null
				|| collect(expectedReturn, actualReturn, methodTypeParameters, bindings, index, selectedSignature, activeAliases);
		}
		final expectedArguments = expected.getTypeArguments();
		// Inherited arguments are evidence from the declared edge, not a change
		// to the operand's concrete type or the shared method signature.
		final owner = expected.getNominalIdentity();
		final ancestor = owner == null || sameTypeConstructor(expected, actual) ? null : TyNominalAncestor.view(index, actual, owner);
		final selected = ancestor == null ? actual : ancestor;
		final actualArguments = selected.getTypeArguments();
		if (!sameTypeConstructor(expected, selected) || expectedArguments.length != actualArguments.length)
			return true;
		for (argumentIndex in 0...expectedArguments.length)
			if (!collect(expectedArguments[argumentIndex], actualArguments[argumentIndex], methodTypeParameters, bindings, index, selectedSignature,
				activeAliases))
				return false;
		return true;
	}

	static function bindings(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<TyTypeParameterId>,
			index:TyperIndex):Null<haxe.ds.StringMap<TyType>> {
		final result = new haxe.ds.StringMap<TyType>();
		for (argumentIndex in 0...suppliedArity) {
			final parameter = TyCallableSignature.argumentParameter(sig, argumentIndex);
			if (parameter == null || argumentIndex >= argTypes.length)
				continue;
			// An optional null argument requests the default; it must not bind a
			// method type parameter to the null-literal type.
			if (parameter.isOptional && argTypes[argumentIndex].isNullLiteral())
				continue;
			if (!collect(parameter.type, argTypes[argumentIndex], methodTypeParameters, result, index))
				return null;
		}
		return result;
	}

	/** Reject a candidate when repeated method parameters infer incompatible types. **/
	public static function argumentsAreConsistent(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<TyTypeParameterId>,
			index:TyperIndex):Bool {
		if (methodTypeParameters.length == 0)
			return true;
		final inferred = bindings(sig, argTypes, suppliedArity, methodTypeParameters, index);
		if (inferred == null)
			return false;
		// Each slot was ranked independently. Recheck structural slots using the
		// shared bindings so two arguments cannot infer different values for T.
		for (slot in 0...suppliedArity) {
			final parameter = TyCallableSignature.argumentParameter(sig, slot);
			if (parameter != null
				&& slot < argTypes.length
				&& TyStructuralArgument.compatibility(index, substitute(parameter.type, methodTypeParameters, inferred, true), argTypes[slot]) == Incompatible)
				return false;
		}
		return true;
	}

	/** Infer a provisional structural slot without mutating the declaration or another candidate's bindings. */
	public static function structuralArgument(expected:TyType, actual:TyType, parameters:Array<TyTypeParameterId>, index:TyperIndex):Null<TyType> {
		final inferred = new haxe.ds.StringMap<TyType>();
		return collect(expected, actual, parameters, inferred, index) ? substitute(expected, parameters, inferred, true) : null;
	}

	/**
		Recover binders from an already-selected signature without repeating inference.
		An explicitly selected Dynamic is a complete type here. Repeated occurrences
		must agree exactly; raw Dynamic arguments remain non-evidence during inference.
	 */
	@:allow(TypedRequiredInlineLowering)
	static function inlineBindings(declaration:TyDeclarationInfo, selectedParameters:Array<TyType>, result:TyType, index:TyperIndex):haxe.ds.StringMap<TyType> {
		final parameters = declaration.getTypeParameterIds();
		final bound = new haxe.ds.StringMap<TyType>();
		final signature = declaration.getSignature();
		final declared = signature.getArgs();
		if (declared.length != selectedParameters.length)
			throw "inline specialization requires an exact selected parameter list";
		for (slot in 0...declared.length)
			if (!collect(declared[slot], selectedParameters[slot], parameters, bound, index, true))
				throw "inline specialization has conflicting parameter evidence";
		if (!collect(signature.getReturnType(), result, parameters, bound, index, true))
			throw "inline specialization has conflicting result evidence";
		for (parameter in parameters)
			if (!bound.exists(parameter.getCanonicalKey()))
				throw "inline specialization lacks type parameter " + parameter.getName();
		return bound;
	}

	static function hasUnbound(type:TyType, methodTypeParameters:Array<TyTypeParameterId>, inferred:haxe.ds.StringMap<TyType>):Bool {
		if (type == null)
			return false;
		final parameter = parameterIdentity(type, methodTypeParameters);
		if (parameter != null)
			return !inferred.exists(parameter.getCanonicalKey());
		if (type.isTypeParameter())
			return false;
		if (type.isNullable())
			return hasUnbound(type.unwrapNull(), methodTypeParameters, inferred);
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				if (hasUnbound(argument, methodTypeParameters, inferred))
					return true;
			final result = type.getFunctionReturn();
			return result != null && hasUnbound(result, methodTypeParameters, inferred);
		}
		for (argument in type.getTypeArguments().concat(type.getAnonymousFieldTypes()))
			if (hasUnbound(argument, methodTypeParameters, inferred))
				return true;
		return false;
	}

	static function substitutedGenericDisplay(source:TyType, arguments:Array<TyType>):String {
		var base = StringTools.trim(source.getDisplay());
		final open = base.indexOf("<");
		if (open >= 0)
			base = StringTools.trim(base.substr(0, open));
		return base.length == 0 ? "" : base + "<" + [for (argument in arguments) argument.getDisplay()].join(",") + ">";
	}

	static function substitute(type:TyType, methodTypeParameters:Array<TyTypeParameterId>, inferred:haxe.ds.StringMap<TyType>, retainOpen:Bool = false):TyType {
		if (type == null)
			return TyType.unknown();
		final parameter = parameterIdentity(type, methodTypeParameters);
		if (parameter != null) {
			final bound = inferred.get(parameter.getCanonicalKey());
			return bound == null ? (retainOpen ? type : TyType.unknown()) : bound;
		}
		if (type.isNullable())
			return TyType.nullable(substitute(type.unwrapNull(), methodTypeParameters, inferred, retainOpen));
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			// Replacing T must keep whether callers may omit or spread each
			// parameter, along with its name and metadata.
			return type.withFunctionTypes([
				for (argument in type.getFunctionArguments())
					substitute(argument, methodTypeParameters, inferred, retainOpen)
			],
				result == null ? TyType.unknown() : substitute(result, methodTypeParameters, inferred, retainOpen));
		}
		if (type.isAnonymous())
			return type.withAnonymousTypes([
				for (field in type.getAnonymousFieldTypes())
					substitute(field, methodTypeParameters, inferred, retainOpen)
			]);
		final arguments = type.getTypeArguments();
		if (arguments.length == 0)
			return type;
		final substituted = [
			for (argument in arguments)
				substitute(argument, methodTypeParameters, inferred, retainOpen)
		];
		final alias = type.getAliasDefinition();
		if (alias != null)
			return TyType.aliasApplication(alias, substituted);
		if (type.isAbstractMeta())
			return TyType.abstractMeta(substituted[0]);
		final identity = type.getNominalIdentity();
		if (identity != null)
			return TyType.nominal(identity, substituted, substitutedGenericDisplay(type, substituted));
		if (type.isUnresolved())
			return TyType.unresolved(type.getUnresolvedPath(), substituted, substitutedGenericDisplay(type, substituted));
		return type;
	}

	/** Keep unsolved method binders for the owning call's inference variables, while retaining concrete argument evidence. */
	public static function inferenceCallable(declaration:TyDeclarationInfo, signature:TyFunSig, actual:Array<TyType>, index:TyperIndex):TyType {
		final parameters = declaration.getTypeParameterIds();
		final inferred = bindings(signature, actual, actual.length, inferableTypeParameters(declaration), index);
		if (inferred == null)
			throw "selected generic call has inconsistent arguments";
		// A preview such as Array<Unknown> is not a concrete binding. Preserve
		// this method binder so direct-call inference links it to the argument's
		// existing variables instead of freezing Unknown inside a copied type.
		for (parameter in parameters) {
			final key = parameter.getCanonicalKey();
			final type = inferred.get(key);
			if (type != null && (type.hasUnknownComponent() || type.isUnresolved()))
				inferred.remove(key);
		}
		final callable = TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType();
		return callable.withFunctionTypes([
			for (type in callable.getFunctionArguments())
				substitute(type, parameters, inferred, true)
		], substitute(callable.getFunctionReturn(), parameters, inferred, true));
	}

	/**
		Specialize a selected declaration's return type, or return `Unknown` when
		argument evidence cannot close every method parameter used by that result.
	**/
	public static function specializeResult(declaration:TyDeclarationInfo, signature:TyFunSig, argTypes:Array<TyType>, index:TyperIndex):TyType {
		final methodTypeParameters = declaration.getTypeParameterIds();
		if (methodTypeParameters.length == 0)
			return signature.getReturnType();
		final inferred = bindings(signature, argTypes, argTypes.length, inferableTypeParameters(declaration), index);
		if (inferred == null || hasUnbound(signature.getReturnType(), methodTypeParameters, inferred))
			return TyType.unknown();
		return substitute(signature.getReturnType(), methodTypeParameters, inferred);
	}

	/**
		Close method parameters from the same evidence used for result specialization.
		The caller has already applied receiver arguments. Keep any remaining owner
		parameter identity: a method inside Box<T> can consume that exact T without
		turning it into an unconstrained Unknown context.
	 */
	public static function specializeParameters(declaration:TyDeclarationInfo, signature:TyFunSig, argTypes:Array<TyType>, index:TyperIndex):Array<TyType> {
		final parameters = declaration.getTypeParameterIds();
		final inferred = bindings(signature, argTypes, argTypes.length, inferableTypeParameters(declaration), index);
		return [
			for (type in signature.getArgs())
				inferred == null || hasUnbound(type, parameters, inferred) ? TyType.unknown() : substitute(type, parameters, inferred)
		];
	}
}

/** What the arguments that reach one unbound method parameter say about its type. **/
private enum TyParameterEvidence {
	/** A concrete, unresolved, or missing argument: the parameter must be bound to pass its bounds. **/
	Constraining;

	/** Only Dynamic (or an unchecked cast passed as Dynamic) reaches it: a dependent bound may close it. **/
	DynamicOnly;

	/** A `null` literal reaches it: upstream's nullable monomorph has already accepted its bounds. **/
	NullOnly;
}
