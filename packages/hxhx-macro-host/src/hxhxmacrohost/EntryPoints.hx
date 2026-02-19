package hxhxmacrohost;

/**
	Generated macro entrypoint registry (Stage 4 bring-up).

	Why
	- Stage 4 starts with a small allowlist of builtin macro entrypoints (`BuiltinMacros.*`) for stability.
	- To move toward real-world macro execution we also need to run *non-builtin* macro modules.
	- The obvious dynamic approach (parse `pack.Class.method()` and invoke via reflection) is not
	  currently viable:
	  - `Reflect.callMethod` is not implemented yet by `reflaxe.ocaml` (portable surface).
	  - Even if it were, we want deterministic, auditably-safe behavior for early gates.

	What
	- `run(expr)` returns `null` if `expr` is not registered.
	- When a generated registry is present, it dispatches exact expression strings to static methods.

	How
	- `scripts/hxhx/build-hxhx-macro-host.sh` can generate `EntryPointsGen.hx` into a build-only
	  classpath and compile it into the macro host binary.
	- Generation is enabled by defining `hxhx_entrypoints` during the macro host build.
**/
class EntryPoints {
	public static function run(_expr:String):Null<String> {
		#if hxhx_entrypoints
		return EntryPointsGen.run(_expr);
		#else
		return null;
		#end
	}
}
