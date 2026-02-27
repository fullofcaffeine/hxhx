package hxhxmacrohost;

/**
	Native macro-module ABI constants for Stage 4 dynlink bring-up.

	Why
	- Native macro modules are loaded at runtime (`Dynlink.loadfile`) and register
	  macro expression entrypoints as load-time side effects.
	- A versioned ABI constant lets us fail fast when host and promoted module
	  conventions diverge.

	What
	- `ABI_VERSION`:
	  - host/plugin contract version (integer, bump on breaking changes).
	- `SNAPSHOT_VERSION`:
	  - encoded registration snapshot version (`NativeMacroModuleHost.snapshot`).
**/
class NativeMacroModuleAbi {
	public static inline final ABI_VERSION:Int = 1;
	public static inline final SNAPSHOT_VERSION:String = "v1";
}
