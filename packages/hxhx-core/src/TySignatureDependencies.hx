/**
	Finds unresolved declaration types before method identities reach typed callers.

	The index already distinguishes local type parameters from module names. Walk
	those facts instead of rescanning source annotations. Loading remains with
	ModuleLoader, which owns source selection and request preparation.
**/

/** Return each missing type path once, including nested signature arguments. */
function unresolved(index:TyperIndex, modulePath:String):Array<String> {
	final paths = new haxe.ds.StringMap<Bool>();
	function visit(type:Null<TyType>):Void {
		if (type == null)
			return;
		if (type.isUnresolved())
			paths.set(type.getUnresolvedPath(), true);
		visit(type.getNullableInner());
		for (argument in type.getTypeArguments())
			visit(argument);
		for (argument in type.getFunctionArguments())
			visit(argument);
		visit(type.getFunctionReturn());
		for (field in type.getAnonymousFieldTypes())
			visit(field);
	}
	for (info in index.getDeclaredByModulePath(modulePath)) {
		for (field in info.getFieldInfos())
			visit(field.getType());
		for (declaration in info.getDeclarations()) {
			final signature = declaration.getSignature();
			for (argument in signature.getArgs())
				visit(argument);
			visit(signature.getReturnType());
		}
		final abstractInfo = index.getAbstractByFullName(info.getFullName());
		if (abstractInfo != null) {
			visit(abstractInfo.getUnderlyingType());
			for (type in abstractInfo.getImplicitFromTypes())
				visit(type);
			for (type in abstractInfo.getImplicitToTypes())
				visit(type);
		}
	}
	final result = [for (path in paths.keys()) path];
	result.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
	return result;
}
