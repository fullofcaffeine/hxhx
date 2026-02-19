/**
	Minimal base class for type-driven module loading during Stage3 typing.

	Why
	- The bootstrap OCaml build can be sensitive to cyclic compilation-unit dependencies.
	- `TyperContext` needs a stable way to ask “can you make this type resolvable?” without
	  directly depending on a concrete loader implementation that may itself need to refer
	  to compiler pipeline types.
	- Using a base class (instead of a Haxe `interface`) keeps the generated OCaml type
	  representation straightforward for the backend.

	What
	- `ensureTypeAvailable(...)` attempts to make `typePath` resolvable by:
	  - locating the corresponding module file,
	  - parsing it,
	  - and indexing it in a shared `TyperIndex`.

	How
	- `ModuleLoader` extends this and performs the real work.
**/
class LazyTypeLoader {
	public function new() {}

	public function ensureTypeAvailable(typePath:String, packagePath:String, imports:Array<String>):Null<TyClassInfo> {
		// Default no-op implementation.
		//
		// Note (OCaml backend):
		// Dune in this repo builds with warnings-as-errors in some configurations. Keep the
		// parameters "used" so generated OCaml doesn't trip unused-var warnings.
		if (typePath == "__hxhx_never__" || packagePath == "__hxhx_never__")
			return null;
		if (imports != null && imports.length == -1)
			return null;
		return null;
	}
}
