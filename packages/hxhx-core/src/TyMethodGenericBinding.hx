/**
	Infers the bounded, unconstrained method-generic relationships that shared
	call typing can currently prove.

	Method parameters are bound from semantic argument types, including nested
	nominal and function shapes. Indexed superclass and interface substitutions
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

	/** Validate inferred direct-call arguments against bounds resolved at their declaration, never caller spellings. */
	public static function constraintFailure(declaration:TyDeclarationInfo, signature:TyFunSig, actual:Array<TyType>, applyBound:TyType->TyType,
			accepts:(TyType, TyType) -> Bool, index:TyperIndex):Null<String> {
		final constraints = declaration.getResolvedTypeParameterConstraints();
		final inferred = bindings(signature, actual, actual.length, inferableTypeParameters(declaration), index);
		for (parameter in declaration.getTypeParameterIds()) {
			final key = parameter.getCanonicalKey();
			if (!constraints.exists(key))
				continue;
			final supplied = inferred == null ? null : inferred.get(key);
			for (constraint in constraints.get(key)) {
				final bound = applyBound(constraint);
				if (bound.hasUnknownComponent()
					|| bound.isUnresolved()
					|| (supplied == null ? !hasOnlyUnconstrainingEvidence(signature, actual,
						parameter) : !accepts(substitute(bound, declaration.getTypeParameterIds(), inferred), supplied)))
					return "Constraint check failure for " + signature.getName() + "." + parameter.getName();
			}
		}
		return null;
	}

	/** Null and explicit Dynamic leave method variables open; unresolved types do not authorize a bound. */
	static function hasOnlyUnconstrainingEvidence(signature:TyFunSig, actual:Array<TyType>, parameter:TyTypeParameterId):Bool {
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
		final expected = signature.getArgs();
		for (index in 0...actual.length)
			if (index < expected.length && contains(expected[index])) {
				if (!actual[index].isNullLiteral() && !actual[index].isDynamic())
					return false;
				found = true;
			}
		return found;
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

	static function collect(expected:TyType, actual:TyType, methodTypeParameters:Array<TyTypeParameterId>, bindings:haxe.ds.StringMap<TyType>,
			index:TyperIndex):Bool {
		if (expected == null || actual == null)
			return true;
		final scheme = actual.getClassValueScheme();
		final context = expected.unwrapNull().getNominalIdentity();
		if (scheme != null && context != null && context.getCanonicalName() == "Class")
			return collect(expected, scheme.preview(), methodTypeParameters, bindings, index);
		// Null carries no concrete type evidence, even for a bare T parameter.
		// Candidate legality is checked separately by overload selection.
		if (actual.isNullLiteral())
			return true;
		final parameter = parameterIdentity(expected, methodTypeParameters);
		if (parameter != null) {
			if (actual.isUnknown() || actual.isDynamic())
				return true;
			final parameterKey = parameter.getCanonicalKey();
			final previous = bindings.get(parameterKey);
			if (previous == null) {
				bindings.set(parameterKey, actual);
				return true;
			}
			final unified = TyType.unify(previous, actual);
			if (unified == null)
				return false;
			bindings.set(parameterKey, unified);
			return true;
		}
		if (expected.isNullable() || actual.isNullable())
			return collect(expected.unwrapNull(), actual.unwrapNull(), methodTypeParameters, bindings, index);
		if (expected.isFunction() || actual.isFunction()) {
			if (!expected.isFunction() || !actual.isFunction())
				return true;
			final expectedArguments = expected.getFunctionArguments();
			final actualArguments = actual.getFunctionArguments();
			if (expectedArguments.length != actualArguments.length)
				return true;
			for (argumentIndex in 0...expectedArguments.length)
				if (!collect(expectedArguments[argumentIndex], actualArguments[argumentIndex], methodTypeParameters, bindings, index))
					return false;
			final expectedReturn = expected.getFunctionReturn();
			final actualReturn = actual.getFunctionReturn();
			return expectedReturn == null
				|| actualReturn == null
				|| collect(expectedReturn, actualReturn, methodTypeParameters, bindings, index);
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
			if (!collect(expectedArguments[argumentIndex], actualArguments[argumentIndex], methodTypeParameters, bindings, index))
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
		return bindings(sig, argTypes, suppliedArity, methodTypeParameters, index) != null;
	}

	/** Recover method binders from an already-selected call signature, without choosing another overload or argument order. */
	@:allow(TypedRequiredInlineLowering)
	static function inlineBindings(declaration:TyDeclarationInfo, selectedParameters:Array<TyType>, result:TyType, index:TyperIndex):haxe.ds.StringMap<TyType> {
		final parameters = declaration.getTypeParameterIds();
		final bound = new haxe.ds.StringMap<TyType>();
		final signature = declaration.getSignature();
		final declared = signature.getArgs();
		if (declared.length != selectedParameters.length)
			throw "inline specialization requires an exact selected parameter list";
		for (slot in 0...declared.length)
			if (!collect(declared[slot], selectedParameters[slot], parameters, bound, index))
				throw "inline specialization has conflicting parameter evidence";
		if (!collect(signature.getReturnType(), result, parameters, bound, index))
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
