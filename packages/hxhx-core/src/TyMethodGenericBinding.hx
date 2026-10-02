/**
	Infers the bounded, unconstrained method-generic relationships that shared
	call typing can currently prove.

	Method parameters are bound from semantic argument types, including nested
	nominal and function shapes. A conflicting binding makes the candidate
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
			accepts:(TyType, TyType) -> Bool):Null<String> {
		final constraints = declaration.getResolvedTypeParameterConstraints();
		final inferred = bindings(signature, actual, actual.length, inferableTypeParameters(declaration));
		for (parameter in declaration.getTypeParameterIds()) {
			final key = parameter.getCanonicalKey();
			if (!constraints.exists(key))
				continue;
			final supplied = inferred == null ? null : inferred.get(key);
			for (constraint in constraints.get(key)) {
				final bound = applyBound(constraint);
				if (bound.hasUnknownComponent()
					|| bound.isUnresolved()
					|| (supplied == null ? !hasOnlyNullEvidence(signature, actual,
						parameter) : !accepts(substitute(bound, declaration.getTypeParameterIds(), inferred), supplied)))
					return "Constraint check failure for " + signature.getName() + "." + parameter.getName();
			}
		}
		return null;
	}

	/** Null leaves its method variable open; unknown non-null arguments are not evidence for this rule. */
	static function hasOnlyNullEvidence(signature:TyFunSig, actual:Array<TyType>, parameter:TyTypeParameterId):Bool {
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
				if (!actual[index].isNullLiteral())
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

	static function collect(expected:TyType, actual:TyType, methodTypeParameters:Array<TyTypeParameterId>, bindings:haxe.ds.StringMap<TyType>):Bool {
		if (expected == null || actual == null)
			return true;
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
		// Null does not determine T when the parameter accepts Null<T>.
		if (expected.isNullable() && actual.isNullLiteral())
			return true;
		if (expected.isNullable() || actual.isNullable())
			return collect(expected.unwrapNull(), actual.unwrapNull(), methodTypeParameters, bindings);
		if (expected.isFunction() || actual.isFunction()) {
			if (!expected.isFunction() || !actual.isFunction())
				return true;
			final expectedArguments = expected.getFunctionArguments();
			final actualArguments = actual.getFunctionArguments();
			if (expectedArguments.length != actualArguments.length)
				return true;
			for (index in 0...expectedArguments.length)
				if (!collect(expectedArguments[index], actualArguments[index], methodTypeParameters, bindings))
					return false;
			final expectedReturn = expected.getFunctionReturn();
			final actualReturn = actual.getFunctionReturn();
			return expectedReturn == null || actualReturn == null || collect(expectedReturn, actualReturn, methodTypeParameters, bindings);
		}
		final expectedArguments = expected.getTypeArguments();
		final actualArguments = actual.getTypeArguments();
		if (!sameTypeConstructor(expected, actual) || expectedArguments.length != actualArguments.length)
			return true;
		for (index in 0...expectedArguments.length)
			if (!collect(expectedArguments[index], actualArguments[index], methodTypeParameters, bindings))
				return false;
		return true;
	}

	static function bindings(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int,
			methodTypeParameters:Array<TyTypeParameterId>):Null<haxe.ds.StringMap<TyType>> {
		final result = new haxe.ds.StringMap<TyType>();
		final expected = sig.getArgs();
		final optional = sig.getArgOptional();
		for (index in 0...suppliedArity) {
			if (index >= expected.length || index >= argTypes.length)
				continue;
			// An optional null argument requests the default; it must not bind a
			// method type parameter to the null-literal type.
			if (index < optional.length && optional[index] && argTypes[index].isNullLiteral())
				continue;
			if (!collect(expected[index], argTypes[index], methodTypeParameters, result))
				return null;
		}
		return result;
	}

	/** Reject a candidate when repeated method parameters infer incompatible types. **/
	public static function argumentsAreConsistent(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<TyTypeParameterId>):Bool {
		return bindings(sig, argTypes, suppliedArity, methodTypeParameters) != null;
	}

	static function hasUnbound(type:TyType, methodTypeParameters:Array<TyTypeParameterId>, inferred:haxe.ds.StringMap<TyType>):Bool {
		if (type == null)
			return false;
		final parameter = parameterIdentity(type, methodTypeParameters);
		if (parameter != null)
			return !inferred.exists(parameter.getCanonicalKey());
		if (type.isNullable())
			return hasUnbound(type.unwrapNull(), methodTypeParameters, inferred);
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				if (hasUnbound(argument, methodTypeParameters, inferred))
					return true;
			final result = type.getFunctionReturn();
			return result != null && hasUnbound(result, methodTypeParameters, inferred);
		}
		for (argument in type.getTypeArguments())
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

	static function substitute(type:TyType, methodTypeParameters:Array<TyTypeParameterId>, inferred:haxe.ds.StringMap<TyType>):TyType {
		if (type == null)
			return TyType.unknown();
		final parameter = parameterIdentity(type, methodTypeParameters);
		if (parameter != null) {
			final bound = inferred.get(parameter.getCanonicalKey());
			return bound == null ? TyType.unknown() : bound;
		}
		if (type.isNullable())
			return TyType.nullable(substitute(type.unwrapNull(), methodTypeParameters, inferred));
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			return TyType.functionType([
				for (argument in type.getFunctionArguments())
					substitute(argument, methodTypeParameters, inferred)
			],
				result == null ? TyType.unknown() : substitute(result, methodTypeParameters, inferred));
		}
		final arguments = type.getTypeArguments();
		if (arguments.length == 0)
			return type;
		final substituted = [for (argument in arguments) substitute(argument, methodTypeParameters, inferred)];
		if (type.isAbstractMeta())
			return TyType.abstractMeta(substituted[0]);
		final identity = type.getNominalIdentity();
		if (identity != null)
			return TyType.nominal(identity, substituted, substitutedGenericDisplay(type, substituted));
		if (type.isUnresolved())
			return TyType.unresolved(type.getUnresolvedPath(), substituted, substitutedGenericDisplay(type, substituted));
		return type;
	}

	/**
		Specialize a selected declaration's return type, or return `Unknown` when
		argument evidence cannot close every method parameter used by that result.
	**/
	public static function specializeResult(declaration:TyDeclarationInfo, signature:TyFunSig, argTypes:Array<TyType>):TyType {
		final methodTypeParameters = declaration.getTypeParameterIds();
		if (methodTypeParameters.length == 0)
			return signature.getReturnType();
		final inferred = bindings(signature, argTypes, argTypes.length, inferableTypeParameters(declaration));
		if (inferred == null || hasUnbound(signature.getReturnType(), methodTypeParameters, inferred))
			return TyType.unknown();
		return substitute(signature.getReturnType(), methodTypeParameters, inferred);
	}
}
