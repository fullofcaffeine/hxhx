package hxhx;

/**
	Plugin registration source tiers for deterministic backend precedence.

	Ordering policy
	- `Explicit`: user-declared plugin entries for the current request.
	- `Bundled`: plugin entries shipped with the distribution.

	Builtin backends are loaded directly by `BackendRegistry` and keep their descriptor
	priority space as the baseline tier below plugin sources.
**/
enum abstract BackendPluginSource(String) to String {
	var Bundled = "bundled";
	var Explicit = "explicit";
}
