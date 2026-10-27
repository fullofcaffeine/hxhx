/**
	Resolve payload types from the enum selected by the switch input.

	Pattern names select members of that exact declaration. Applied enum arguments
	replace its generic binders before child patterns declare locals. A same-named
	constructor from another enum cannot supply payload types. Non-enum inputs
	remain with the existing pattern analysis.
 */
function resolve(input:TyType, name:String, arity:Int, context:TyperContext, position:HxPos):Null<Array<TyType>> {
	if (input == null || context == null || context.getIndex() == null)
		return null;
	var type = input;
	while (type.isNullable())
		type = type.unwrapNull();
	final identity = type.getNominalIdentity();
	final owner = identity == null ? null : context.getIndex().getByFullName(identity.getCanonicalName());
	if (owner == null || !owner.getIsEnum())
		return null;
	function reject(reason:String):Void {
		throw new TyperError(context.getFilePath(), position, "Invalid enum pattern " + name + ": " + reason);
	}
	final dot = name.lastIndexOf(".");
	final member = dot < 0 ? name : name.substr(dot + 1);
	if (dot >= 0) {
		final qualifier = context.resolveType(name.substr(0, dot));
		if (qualifier == null || !qualifier.getIdentity().equals(identity))
			reject("constructor belongs to another enum");
	}
	final signature = owner.staticMethod(member);
	final declaration = signature == null ? null : owner.declarationForSignature(signature);
	if (declaration == null || !declaration.getIsEnumConstructor() || !declaration.getOwner().equals(identity))
		reject("constructor does not belong to " + identity.getCanonicalName());
	final arguments = signature.getArgs();
	if (!acceptsArity(signature, arity))
		reject("expected " + arguments.length + " payload patterns but received " + arity);
	// The nominal index also contains abstracts. Only the validated enum class
	// declaration owns the generic binders used by its constructor signatures.
	if (!Std.isOfType(owner, TyClassInfo))
		reject("missing enum declaration binders");
	final enumOwner:TyClassInfo = cast owner;
	final substitutions = TyTypeSubstitution.bind(enumOwner.getTypeParameterIds(), type.getTypeArguments(), identity.getCanonicalName());
	final optional = signature.getArgOptional();
	// An omitted enum argument remains null in the stored payload. Pattern locals
	// must retain that possibility, including after generic substitution.
	return [
		for (index in 0...arity) {
			final argument = TyTypeSubstitution.apply(arguments[index], substitutions);
			index < optional.length
		&& optional[index] && !argument.isNullable() ? TyType.nullable(argument) : argument;
		}
	];
}

/** A pattern may omit a suffix only when every omitted declaration slot is optional. */
function acceptsArity(signature:TyFunSig, arity:Int):Bool {
	if (signature == null || arity < 0 || arity > signature.getArgs().length)
		return false;
	final optional = signature.getArgOptional();
	for (index in arity...signature.getArgs().length)
		if (index >= optional.length || !optional[index])
			return false;
	return true;
}
