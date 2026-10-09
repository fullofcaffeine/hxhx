/**
	A function type's argument declaration after its type has been resolved.

	Optionality is separate from nullability: callers may omit an optional
	argument, while a nullable required argument must still be supplied. Names
	and metadata remain available to typed projections and diagnostics.
 */
typedef TyFunctionParameter = {
	final name:Null<String>;
	final type:TyType;
	final isOptional:Bool;

	/** Rest parameters store the element type; packing belongs to target call emission. */
	final isRest:Bool;

	final metadata:Array<String>;
};

/** Copy mutable metadata while preserving the immutable semantic type. */
function copy(parameter:TyFunctionParameter):TyFunctionParameter {
	return withType(parameter, parameter.type);
}

/**
	An omitted question-mark parameter or explicit null default stays nullable.
	The public signature still owns the written value type and omission flag.
	A concrete default instead initializes that declared value before body effects.
 */
function declarationBodyType(type:TyType, argument:HxFunctionArg):TyType {
	// Rest omission supplies an empty collection, not a missing nullable value.
	// The method parser's omission flag must not change that body contract.
	if (HxFunctionArg.getIsRest(argument))
		return type;
	final nullable = switch HxFunctionArg.getDefaultValue(argument) {
		case NoDefault: HxFunctionArg.getIsOptional(argument);
		case Default(expression): isNullDefault(expression);
	};
	return nullable && !type.isNullable() ? TyType.nullable(type) : type;
}

/** Parentheses preserve the null literal's parameter-entry contract. */
private function isNullDefault(expression:HxExpr):Bool {
	return switch expression {
		case ENull: true;
		case EParenthesized(inner, _): isNullDefault(inner);
		case _: false;
	};
}

/** Substitute an argument type without discarding its declaration facts. */
function withType(parameter:TyFunctionParameter, type:TyType):TyFunctionParameter {
	return {
		name: parameter.name,
		type: type,
		isOptional: parameter.isOptional,
		isRest: parameter.isRest,
		metadata: parameter.metadata.copy()
	};
}

/**
	Recognize a required standard Rest container after name resolution or substitution.

	Spelling alone cannot establish this fact: a local Rest alias can mean Array.
	An optional Rest parameter still takes one optional container in Haxe 4.3.7.
	An existing rest marker already describes its element, which may itself be Rest.
 */
function normalizeRest(parameter:TyFunctionParameter):TyFunctionParameter {
	if (parameter.isRest || parameter.isOptional)
		return copy(parameter);
	final identity = parameter.type.getNominalIdentity();
	final arguments = parameter.type.getTypeArguments();
	if (identity == null || identity.getCanonicalName() != "haxe.Rest" || arguments.length != 1)
		return copy(parameter);
	return {
		name: parameter.name,
		type: arguments[0],
		isOptional: false,
		isRest: true,
		metadata: parameter.metadata.copy()
	};
}
