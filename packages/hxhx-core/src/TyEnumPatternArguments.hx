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
	if (arguments.length != arity)
		reject("expected " + arguments.length + " payload patterns but received " + arity);
	// The nominal index also contains abstracts. Only the validated enum class
	// declaration owns the generic binders used by its constructor signatures.
	if (!Std.isOfType(owner, TyClassInfo))
		reject("missing enum declaration binders");
	final enumOwner:TyClassInfo = cast owner;
	final substitutions = TyTypeSubstitution.bind(enumOwner.getTypeParameterIds(), type.getTypeArguments(), identity.getCanonicalName());
	return [for (argument in arguments) TyTypeSubstitution.apply(argument, substitutions)];
}
