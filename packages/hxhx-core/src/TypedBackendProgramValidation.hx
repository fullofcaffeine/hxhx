/**
	Checks whole-program typed backend projections before target publication.

	This stateless validation lives outside `TypedBackendModuleProjection` so the
	generated projection module does not depend on `TypedModule`, which already
	depends on the projection and would create an OCaml module cycle.
**/
function assertRuntimeTypeOperandsAbsent(modules:Array<TypedModule>, consumer:String):Void {
	for (module in modules)
		module.getBackendProjection().assertRuntimeTypeOperandsAbsent(consumer);
}
