/**
	Resolve ordinary receiver declarations before field or method lookup. Primitive
	values use their real core provider, so String members do not depend on another
	module having loaded String first. No member types or signatures live here.
 */
function owner(receiver:TyType, context:TyperContext):Null<TyNominalInfo> {
	if (context.getIndex() == null)
		return null;
	final value = TyAliasExpansion.revealNonNullable(receiver);
	final identity = value.getNominalIdentity();
	if (identity != null)
		return context.getIndex().getByFullName(identity.getCanonicalName());
	return value.isPrimitive() ? context.resolvePrimitiveProvider(value) : null;
}

/**
	Reject an absent call after declared fields, methods and extensions failed.
	Dynamic, explicit untyped syntax and incomplete inference remain owned by
	their existing call paths. Abstract forwarding and compiler-provided enum
	operations are not closed class inventories and cannot prove absence here.
 */
function rejectAbsent(input:{
	receiver:TyType,
	member:String,
	provider:Null<TyNominalInfo>,
	hasValueField:Bool,
	unchecked:Bool,
	context:TyperContext,
	position:HxPos
}):Void {
	final value = TyAliasExpansion.revealNonNullable(input.receiver);
	if (input.unchecked || input.hasValueField || value.isDynamic() || value.hasUnknownComponent())
		return;
	if (!value.isAnonymous() && !classProvesAbsence(input.provider, input.member, input.context.getIndex(), []))
		return;
	if (TyNominalApplication.dynamicMemberType(input.context.getIndex(), value) != null)
		return;
	throw new TyperError(input.context.getFilePath(), input.position, value.getDisplay() + " has no field " + input.member);
}

/**
	Absence requires every inherited declaration, including interface parents.
	An unresolved edge or dynamic-member marker cannot prove a member is absent.
	This query does not select a method or infer its signature; existing call
	typing owns those operations. The path guard also rejects cyclic evidence.
 */
private function classProvesAbsence(provider:Null<TyNominalInfo>, member:String, index:TyperIndex, path:Array<String>):Bool {
	if (index == null || !Std.isOfType(provider, TyClassInfo))
		return false;
	// The declaration kind is checked before narrowing to class header facts.
	final declaration:TyClassInfo = cast provider;
	if (declaration.getIsEnum())
		return false;
	final name = declaration.getFullName();
	if (path.indexOf(name) >= 0
		|| declaration.hasField(member)
		|| declaration.propertyInfo(member) != null
		|| declaration.instanceMethodCandidates(member).length > 0
		|| declaration.getDynamicMemberType() != null)
		return false;
	path.push(name);
	final parents = declaration.getDeclaredInterfaceTypes();
	final superclass = declaration.getSuperType();
	if (superclass != null)
		parents.push(superclass);
	for (parent in parents) {
		final identity = parent.getNominalIdentity();
		if (identity == null || !classProvesAbsence(index.getByFullName(identity.getCanonicalName()), member, index, path))
			return false;
	}
	path.pop();
	return true;
}
