/**
	Retain the first applicable signature from one authored metadata-overload
	group. The primary declaration comes first, followed by its metadata order.
	Separate overload declarations have separate implementation owners and still
	participate in ordinary specificity and ambiguity checks. Call this only after
	a candidate passes its argument and constraint checks; rejected candidates
	must not prevent later alternatives from being considered.
 */
function accept(declaration:Null<TyDeclarationInfo>, selected:Array<TyDeclarationInfo>):Bool {
	if (declaration == null)
		return true;
	final owner = declaration.getImplementation();
	if (selected.indexOf(owner) >= 0)
		return false;
	selected.push(owner);
	return true;
}
