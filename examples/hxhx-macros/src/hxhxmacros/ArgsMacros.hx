package hxhxmacros;

import haxe.macro.Compiler;

/**
	Stage4 bring-up macro module: entrypoints with String arguments.

	Why
	- Early Stage4 macro execution is intentionally allowlist-based: we dispatch exact `--macro`
	  expression strings to known entrypoints compiled into the macro host binary.
	- The first registry rung supported only `pack.Class.method()` (no args), which is too limited
	  for many real-world macro initializers and for upstream-style helpers.

	What
	- `setArg(v)` defines `HXHX_ARG=<v>` via `haxe.macro.Compiler.define(...)`.
	- This is used by `scripts/test-hxhx-targets.sh` to assert that:
	  - the allowlist registry can match expressions with a String literal argument, and
	  - reverse RPC define propagation still works.

	How
	- At runtime in the macro host, `haxe.macro.Compiler.define` is overridden (see
	  `tools/hxhx-macro-host/overrides/haxe/macro/Compiler.hx`) and lowered to a reverse-RPC call
	  back into the compiler process.
**/
class ArgsMacros {
	public static function setArg(v:String):Void {
		Compiler.define("HXHX_ARG", v == null ? "" : v);
	}
}

