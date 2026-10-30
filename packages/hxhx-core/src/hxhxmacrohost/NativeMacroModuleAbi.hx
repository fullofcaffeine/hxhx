package hxhxmacrohost;

/**
	Native macro-module ABI constants for Stage 4 dynlink bring-up.

	Why
	- Native macro modules are loaded at runtime (`Dynlink.loadfile`) and register one
	  callback per project macro declaration (`pack.Type.method`) as a load-time side effect.
	- A versioned ABI constant lets us fail fast when host and promoted module
	  conventions diverge.

	What
	- `ABI_VERSION`:
	  - host/plugin contract version (integer, bump on breaking changes).
	  - Version 2 replaced the no-argument `unit -> string` exact-expression handler with
		`register_macro_declaration(plugin, declaration, payload -> payload)`; version 1
		receipts and plugins are rejected.
	- `MACRO_API_VERSION`:
	  - macro entrypoint contract version (integer, bump on incompatible macro API changes).
	- `SNAPSHOT_VERSION`:
	  - encoded registration snapshot version (`NativeMacroModuleHost.snapshot`).
**/
class NativeMacroModuleAbi {
	public static inline final ABI_VERSION:Int = 2;
	public static inline final MACRO_API_VERSION:Int = 1;
	public static inline final SNAPSHOT_VERSION:String = "v3";
}
