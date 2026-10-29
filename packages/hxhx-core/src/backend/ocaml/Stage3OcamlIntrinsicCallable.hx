package backend.ocaml;

/**
	Resolve saved standard-library output functions to the existing native runtime.
	A stable runtime function preserves identity across repeated reads. Its input
	is the ordinary Dynamic carrier, so existing call conversion still owns boxing.
	User methods with the same name retain their own implementation.
 */
function reference(declaration:TyDeclarationInfo):Null<String> {
	if (declaration == null
		|| !declaration.getIsStatic()
		|| declaration.getOwner().getCanonicalName() != "Sys"
		|| declaration.getModulePath() != "Sys"
		|| declaration.getHasBody()
		|| declaration.getIsDynamic()
		|| declaration.getSignature().getName() != "println")
		return null;
	final signature = declaration.getSignature();
	final arguments = signature.getArgs();
	if (arguments.length != 1
		|| arguments[0].getSemanticKey() != "dynamic"
		|| signature.getReturnType().getSemanticKey() != "primitive:Void")
		throw "OCaml Sys.println callable has an unsupported provider signature";
	return "HxSys.printlnValue";
}

/** Only an original callable occurrence with an effect-free type qualifier can select the runtime function. */
function emitValue(expression:HxExpr, lookup:HxExpr->Null<TypedExpr>):Null<String> {
	if (lookup == null)
		return null;
	switch expression {
		case EField(_, "println"):
		case _:
			return null;
	}
	final source = lookup(expression);
	if (source == null || source.getTag() != FieldRead)
		return null;
	final receivers = source.getExpressions();
	if (receivers.length != 1 || receivers[0].getTag() != RuntimeTypeValue)
		return null;
	return reference(source.getDeclaration());
}
