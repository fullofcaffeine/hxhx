package backend.ocaml;

/** Only the builtin Stage3 OCaml emitter can request its native Map operations. */
function forBackend(selected:backend.TargetDescriptor):Null<TyDeclarationInfo->Bool> {
	final builtin = OcamlStage3Backend.descriptor();
	return selected != null && selected.id == builtin.id && selected.implId == builtin.implId ? retain : null;
}

/**
	Keep exact standard `Map<K, V>` operations as calls for the Stage3 emitter.

	The `Map` abstract's inline bodies forward to its backing value through the
	`haxe.Constraints.IMap` interface. Expanding them would leave interface
	calls that Stage3 binds to empty placeholders. Kept as `Map` calls, they
	still carry the applied key and value types, so `Stage3OcamlMapCalls` can
	render the `HxMap` table that `new Map()` allocated for that key type.
 */
function retain(declaration:TyDeclarationInfo):Bool
	return Stage3OcamlMapCalls.retainsAbstractDeclaration(declaration);
