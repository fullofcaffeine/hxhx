package backend.cpp;

/**
	Enum<T> stores an enum descriptor, independently of the abstract's backing type.
	Require the current core abstract and its exact parameter shape. This does not
	authorize enum instance allocation or conversions between different enum types.
 */
function selects(program:CppTypedProgramProjection, type:TyType):Bool {
	CppManagedClosureAbi.assertComplete(type);
	final identity = type.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Enum")
		return false;
	program.assertPlanningCurrent();
	final facts = program.requireClass(program.requireClassIdentity("Enum")).requireSemanticFacts();
	if (type.getTypeArguments().length != 1 || facts.getTypeParameterIds().length != 1)
		throw "managed enum handle requires the exact Enum type parameter";
	return switch facts.getNominalKind() {
		case AbstractValue(_): true;
		case _: throw "managed enum handle requires the core abstract declaration";
	};
}

/** EnumValue is the core instance view; its absent abstract backing type does not erase enum storage. */
function selectsInstanceView(program:CppTypedProgramProjection, type:TyType):Bool {
	CppManagedClosureAbi.assertComplete(type);
	final identity = type.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "EnumValue")
		return false;
	program.assertPlanningCurrent();
	final facts = program.requireClass(program.requireClassIdentity("EnumValue")).requireSemanticFacts();
	if (type.getTypeArguments().length != 0 || facts.getTypeParameterIds().length != 0 || !facts.getNominalKind().match(AbstractValue(_)))
		throw "managed enum instance view requires the exact core abstract";
	return true;
}

/** A checked enum-to-EnumValue transfer keeps the original instance and its descriptor. */
function permitsInstanceView(program:CppTypedProgramProjection, target:TyType, source:TyType):Bool {
	if (!selectsInstanceView(program, target.unwrapNull()))
		return false;
	final selected = source.unwrapNull();
	if (selected.isDynamic())
		return true;
	final identity = selected.getNominalIdentity();
	if (identity == null)
		return false;
	final facts = program.requireClass(program.requireClassIdentity(identity.getCanonicalName())).requireSemanticFacts();
	return facts.getNominalKind().match(EnumValue)
		&& !facts.getIsExtern()
		&& selected.getTypeArguments().length == facts.getTypeParameterIds().length;
}
