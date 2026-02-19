package backend;

/**
	Backend capability flags for Stage3 emission.

	Why
	- Stage3 currently has one linked backend (`ocaml-stage3`), but we are introducing
	  additional builtin targets (starting with `js-native`).
	- The driver needs a small, explicit contract to understand what a backend can do
	  (for example, whether it supports build/executable output or "no-emit" style runs).

	What
	- `supportsNoEmit`: backend can participate in type+macro-only runs where emission is skipped.
	- `supportsBuildExecutable`: backend can emit and build a runnable artifact in one step.
	- `supportsCustomOutputFile`: backend supports a concrete output file hint (for targets like JS).

	How
	- Keep this type intentionally minimal for the first extraction rung.
	- Expand only when a concrete Stage3 workflow needs another capability bit.
**/
typedef BackendCapabilities = {
	final supportsNoEmit:Bool;
	final supportsBuildExecutable:Bool;
	final supportsCustomOutputFile:Bool;
}
