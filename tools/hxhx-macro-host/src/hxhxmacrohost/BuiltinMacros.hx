package hxhxmacrohost;

import hxhxmacrohost.api.Compiler;
import hxhxmacrohost.api.Context;

/**
	Builtin macro entrypoints compiled into the Stage 4 macro host.

	Why
	- Stage 4’s end goal is to execute *user-provided* macro modules without stage0.
	- Before we can do that, we need a “first rung” that proves the core mechanism:
	  - parse a macro expression,
	  - dispatch to a macro function,
	  - allow that macro to query Context and produce effects (defines / generated output),
	  - return a deterministic result.

	What
	- `smoke()` is the minimal “real macro” used by tests:
	  - queries `Context.getType("String")`
	  - writes a define via `Compiler.define`
	  - returns a small report string

	How
	- Dispatched by `hxhxmacrohost.Main` when it receives `macro.run` for a matching expression.
	- This is intentionally not public API: it is a bootstrap tool used to validate Stage 4 bring-up.
**/
class BuiltinMacros {
	public static function smoke():String {
		final t = Context.getType("String");
		Compiler.define("HXHX_SMOKE", "1");
		return "smoke:type=" + t + ";define=" + (Context.defined("HXHX_SMOKE") ? "yes" : "no");
	}

	public static function fail():String {
		return MacroError.raise("intentional macro host failure (for position payload tests)");
	}
}
