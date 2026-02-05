package hxhxmacrohost;

/**
	Stage 4 macro host runtime state (bring-up).

	Why
	- In the Model A design, the macro host is a long-running process that serves RPC requests.
	- Even in the earliest rungs, we need a single place to store “macro runtime” state:
	  - a define store (for `Compiler.define` and `Context.defined*`)
	  - small builtin type tables (for `Context.getType` bring-up)
	- Keeping this state centralized makes it possible to evolve toward:
	  - per-compilation reset,
	  - macro server reuse,
	  - structured protocol messages carrying typed data.

	What
	- `defines`: a name → string map that models compiler defines at macro-time.
	- `builtinTypes`: a tiny allowlist used by `Context.getType` during bring-up.

	How
	- Initialized once at macro host startup by `hxhxmacrohost.Main`.
	- Accessed by the OCaml-native “macro API” shims under `hxhxmacrohost.api.*`.

	Portability note
	- This is macro-host-internal code (Haxe compiled to OCaml). It intentionally does not rely
	  on host-specific shims beyond basic stdin/stdout transport, so later non-OCaml builds of
	  `hxhx` can keep the same structure and swap transport implementations.
**/
class MacroRuntime {
	/**
		Define store for macro-time `Compiler.define` and `Context.defined*` behavior.

		Note: this is intentionally initialized once per macro host process. The early Stage 4 runner
		spawns a fresh macro host per call, so per-compilation reset is implicitly covered.
	**/
	public static var defines(default, null):Map<String, String> = [];

	public static function builtinTypeDesc(name:String):String {
		return switch (name) {
			case "Int", "Float", "Bool", "String", "Void":
				"builtin:" + name;
			case _:
				"unknown:" + name;
		}
	}
}
