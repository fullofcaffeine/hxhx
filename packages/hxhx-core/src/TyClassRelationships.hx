/** Resolved interface parents and the separate type of undeclared extern members. */
typedef TyClassRelationships = {
	final interfaces:Array<TyType>;
	final dynamicMemberType:Null<TyType>;
}

/**
	Separate the core Dynamic<T> marker from ordinary interface inheritance.
	The marker permits undeclared instance members of type T on extern classes.
	It supplies no interface methods, dispatch table, or superclass constructor.
	Keep source header types separately so final resolution can verify identity.
 */
function resolve(types:Array<TyType>, isInterface:Bool, isExtern:Bool):TyClassRelationships {
	final interfaces = new Array<TyType>();
	var dynamicMemberType:Null<TyType> = null;
	for (type in types) {
		var core = type;
		while (core.isNullable())
			core = core.unwrapNull();
		final identity = core.getNominalIdentity();
		final marker = core.isDynamic() || (identity != null && identity.getCanonicalName() == "StdTypes.Dynamic");
		if (!marker) {
			interfaces.push(type);
			continue;
		}
		if (isInterface || !isExtern)
			throw "implements Dynamic is only supported on extern classes";
		if (dynamicMemberType != null)
			throw "Cannot have several dynamics";
		final arguments = core.getTypeArguments();
		if (arguments.length > 1)
			throw "Too many parameters for Dynamic";
		dynamicMemberType = arguments.length == 0 ? TyType.fromHintText("Dynamic") : arguments[0];
	}
	return {interfaces: interfaces, dynamicMemberType: dynamicMemberType};
}
