/**
	Resolve the superclass type already selected by the declaration index.
	Its arguments retain the current class's exact generic binders. Static code,
	interfaces, abstracts, and classes without a parent have no super receiver.
 */
function resolve(owner:Null<TyNominalInfo>, isStatic:Bool):TyType {
	if (isStatic || owner == null || !Std.isOfType(owner, TyClassInfo))
		return TyType.unknown();
	// The nominal index includes enums and abstracts; validate before narrowing.
	final parent = (cast owner : TyClassInfo).getSuperType();
	return parent == null ? TyType.unknown() : parent;
}
