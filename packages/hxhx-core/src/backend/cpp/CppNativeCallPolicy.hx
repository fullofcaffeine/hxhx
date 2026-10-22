package backend.cpp;

/** Only the selected builtin implementation can request C++'s native storage operations. */
function forBackend(selected:backend.TargetDescriptor):Null<TyDeclarationInfo->Bool> {
	final builtin = CppNativeBackend.descriptor();
	return selected.id == builtin.id && selected.implId == builtin.implId ? retain : null;
}

/**
	Keep exact standard Map operations for C++'s managed storage bindings.

	Expanding their authored forwarding bodies would substitute IMap interface
	calls, whose ordinary class dispatch cannot access native Map payloads.
	Only operations implemented by this target are retained. Emission must still
	validate the exact occurrence, signature, applied types, and storage contract.
	Other targets omit this policy and use the authored method bodies.
 */
function retain(declaration:TyDeclarationInfo):Bool {
	return CppManagedMapGet.selectsDeclaration(declaration) || CppManagedMapSet.selectsDeclaration(declaration);
}
