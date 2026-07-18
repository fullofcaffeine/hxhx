/**
	Infers the bounded, unconstrained method-generic relationships that shared
	call typing can currently prove.

	Method parameters are bound from semantic argument types, including nested
	nominal and function shapes. A conflicting binding makes the candidate
	inapplicable. A parameter that is still open in the selected return type
	produces `Unknown` instead of escaping into a caller-local type hint where a
	backend could mistake it for an unrelated class.

	Constrained method parameters remain deliberately outside this helper until
	the shared typer can validate their constraints. Target carriers and rendered
	type names are never binding evidence.
**/
class TyMethodGenericBinding {
	static function parameterName(type:TyType, methodTypeParameters:Array<String>):Null<String> {
		if (type == null || !type.isTypeParameter() || methodTypeParameters == null)
			return null;
		final name = type.getDisplay();
		return methodTypeParameters.indexOf(name) < 0 ? null : name;
	}

	/** Return the method parameters whose constraints need no further proof. **/
	public static function inferableTypeParameters(declaration:Null<TyDeclarationInfo>):Array<String> {
		if (declaration == null)
			return [];
		final constraints = declaration.getTypeParameterConstraints();
		return [
			for (name in declaration.getTypeParameters())
				if (!constraints.exists(name)) name
		];
	}

	/** Whether this exact semantic type is one of the inferable method parameters. **/
	public static function isInferableParameter(type:TyType, methodTypeParameters:Array<String>):Bool {
		return parameterName(type, methodTypeParameters) != null;
	}

	/** Compare the semantic constructors around nested generic arguments. **/
	public static function sameTypeConstructor(left:TyType, right:TyType):Bool {
		if (left == null || right == null)
			return false;
		final leftIdentity = left.getNominalIdentity();
		final rightIdentity = right.getNominalIdentity();
		if (leftIdentity != null || rightIdentity != null)
			return leftIdentity != null && rightIdentity != null && leftIdentity.getCanonicalName() == rightIdentity.getCanonicalName();
		return left.isUnresolved() && right.isUnresolved() && left.getUnresolvedPath() == right.getUnresolvedPath();
	}

	static function collect(expected:TyType, actual:TyType, methodTypeParameters:Array<String>, bindings:haxe.ds.StringMap<TyType>):Bool {
		if (expected == null || actual == null)
			return true;
		final parameter = parameterName(expected, methodTypeParameters);
		if (parameter != null) {
			if (actual.isUnknown() || actual.isDynamic())
				return true;
			final previous = bindings.get(parameter);
			if (previous == null) {
				bindings.set(parameter, actual);
				return true;
			}
			final unified = TyType.unify(previous, actual);
			if (unified == null)
				return false;
			bindings.set(parameter, unified);
			return true;
		}
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

	static function bindings(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<String>):Null<haxe.ds.StringMap<TyType>> {
		final result = new haxe.ds.StringMap<TyType>();
		final expected = sig.getArgs();
		for (index in 0...suppliedArity) {
			if (index >= expected.length || index >= argTypes.length)
				continue;
			if (!collect(expected[index], argTypes[index], methodTypeParameters, result))
				return null;
		}
		return result;
	}

	/** Reject a candidate when repeated method parameters infer incompatible types. **/
	public static function argumentsAreConsistent(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<String>):Bool {
		return bindings(sig, argTypes, suppliedArity, methodTypeParameters) != null;
	}

	static function hasUnbound(type:TyType, methodTypeParameters:Array<String>, inferred:haxe.ds.StringMap<TyType>):Bool {
		if (type == null)
			return false;
		final parameter = parameterName(type, methodTypeParameters);
		if (parameter != null)
			return !inferred.exists(parameter);
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

	static function substitute(type:TyType, methodTypeParameters:Array<String>, inferred:haxe.ds.StringMap<TyType>):TyType {
		if (type == null)
			return TyType.unknown();
		final parameter = parameterName(type, methodTypeParameters);
		if (parameter != null) {
			final bound = inferred.get(parameter);
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
		final methodTypeParameters = declaration.getTypeParameters();
		if (methodTypeParameters.length == 0)
			return signature.getReturnType();
		final inferred = bindings(signature, argTypes, argTypes.length, inferableTypeParameters(declaration));
		if (inferred == null || hasUnbound(signature.getReturnType(), methodTypeParameters, inferred))
			return TyType.unknown();
		return substitute(signature.getReturnType(), methodTypeParameters, inferred);
	}
}
