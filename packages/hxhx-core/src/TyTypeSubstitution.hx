/**
	Apply exact type-parameter bindings to the structural semantic type model.

	The operation walks `TyType` constructors directly. It never parses a
	diagnostic display string or a cache identity, so nested nullable, function,
	anonymous, nominal, and unresolved types keep the meaning selected by typing.
**/
class TyTypeSubstitution {
	/** Return every structural type-parameter name in deterministic order. **/
	public static function parameterNames(type:TyType):Array<String> {
		return [for (parameter in parameterIdentities(type)) parameter.getName()];
	}

	/** Return every exact structural type-parameter identity in deterministic order. **/
	public static function parameterIdentities(type:TyType):Array<TyTypeParameterId> {
		if (type == null)
			throw "semantic type parameter scan received a null type";
		final found = new haxe.ds.StringMap<TyTypeParameterId>();
		function visit(current:TyType):Void {
			final parameter = current.getTypeParameterIdentity();
			if (parameter != null) {
				found.set(parameter.getCanonicalKey(), parameter);
				return;
			}
			if (current.isNullable()) {
				visit(current.unwrapNull());
				return;
			}
			if (current.isFunction()) {
				for (argument in current.getFunctionArguments())
					visit(argument);
				final result = current.getFunctionReturn();
				if (result != null)
					visit(result);
				return;
			}
			if (current.isAnonymous())
				for (fieldType in current.getAnonymousFieldTypes())
					visit(fieldType);
			for (argument in current.getTypeArguments())
				visit(argument);
		}
		visit(type);
		final keys = [for (key in found.keys()) key];
		keys.sort((left, right) -> Reflect.compare(left, right));
		final out = [for (key in keys) found.get(key)];
		return out;
	}

	/**
		Bind declared parameters to applied arguments with an exact arity check.

		The returned map is private to the caller. Parameter names must be unique,
		and every supplied argument must be a semantic type.
	**/
	public static function bind(parameters:Array<TyTypeParameterId>, arguments:Array<TyType>, context:String):haxe.ds.StringMap<TyType> {
		final actualParameters = parameters == null ? [] : parameters;
		final actualArguments = arguments == null ? [] : arguments;
		final owner = normalize(context);
		if (actualParameters.length != actualArguments.length)
			throw "semantic type substitution arity mismatch for " + owner + ": expected " + actualParameters.length + " arguments but received "
				+ actualArguments.length;
		final bindings = new haxe.ds.StringMap<TyType>();
		for (index in 0...actualParameters.length) {
			final parameter = actualParameters[index];
			final argument = actualArguments[index];
			if (parameter == null || argument == null)
				throw "semantic type substitution contains an incomplete binding for " + owner;
			final parameterKey = parameter.getCanonicalKey();
			if (bindings.exists(parameterKey))
				throw "semantic type substitution contains duplicate parameter " + parameter.getName() + " for " + owner;
			bindings.set(parameterKey, argument);
		}
		return bindings;
	}

	/** Create an identity binding for the open parameters of a generic class. **/
	public static function identity(parameters:Array<TyTypeParameterId>, context:String):haxe.ds.StringMap<TyType> {
		final actualParameters = parameters == null ? [] : parameters;
		return bind(actualParameters, [for (parameter in actualParameters) TyType.typeParameter(parameter)], context);
	}

	/**
		Substitute every parameter present in `bindings`.

		An unbound parameter remains explicit. This is required when a generic
		child passes one of its own still-open parameters to a generic parent.
	**/
	public static function apply(type:TyType, bindings:haxe.ds.StringMap<TyType>):TyType {
		if (type == null)
			throw "semantic type substitution received a null type";
		if (type.isTypeParameter()) {
			final parameter = type.getTypeParameterIdentity();
			final parameterKey = parameter == null ? null : parameter.getCanonicalKey();
			if (parameterKey != null && bindings != null && bindings.exists(parameterKey)) {
				final bound = bindings.get(parameterKey);
				if (bound == null)
					throw "semantic type substitution contains a null binding for " + parameter.getName();
				return bound;
			}
			return type;
		}
		if (type.isNullable())
			return TyType.nullable(apply(type.unwrapNull(), bindings));
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			return TyType.functionType([for (argument in type.getFunctionArguments()) apply(argument, bindings)],
				result == null ? TyType.unknown() : apply(result, bindings));
		}
		if (type.isAnonymous())
			return TyType.anonymous(type.getAnonymousFieldNames(), [for (fieldType in type.getAnonymousFieldTypes()) apply(fieldType, bindings)]);

		final arguments = type.getTypeArguments();
		if (arguments.length == 0)
			return type;
		final substitutedArguments = [for (argument in arguments) apply(argument, bindings)];
		final nominalIdentity = type.getNominalIdentity();
		if (nominalIdentity != null)
			return TyType.nominal(nominalIdentity, substitutedArguments);
		if (type.isUnresolved())
			return TyType.unresolved(type.getUnresolvedPath(), substitutedArguments);
		throw "semantic type substitution cannot rebuild type " + type.getSemanticKey();
	}

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
