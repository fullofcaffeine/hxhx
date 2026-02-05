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

	/**
		Generate an OCaml module in the compiler output (Stage 4 bring-up).

		Why
		- This is our first “macro generates code” rung without implementing full typed AST transforms.
		- Upstream macros can generate classes/fields; we start by generating a target module file,
		  proving the artifact plumbing works end-to-end.

		What
		- Emits a module `HxHxGen` with a single value `generated`.
		- Defines `HXHX_GEN=1` so the compiler can observe that generation occurred.
	**/
	public static function genModule():String {
		final t = Context.getType("String");
		final src = "let generated : string = \"" + t + "\"";
		Compiler.emitOcamlModule("HxHxGen", src);
		Compiler.define("HXHX_GEN", "1");
		return "genModule=ok";
	}

	/**
		Add a classpath from an environment variable.

		Why
		- Our macro expression allowlist does not parse arguments yet.
		- This lets CI tests pass a path deterministically without growing expression parsing.

		What
		- Reads `HXHX_ADD_CP` and calls `Compiler.addClassPath` if it is non-empty.
	**/
	public static function addCpFromEnv():String {
		final cp = Sys.getEnv("HXHX_ADD_CP");
		if (cp != null && StringTools.trim(cp).length > 0) {
			Compiler.addClassPath(cp);
			return "addCp=ok";
		}
		return "addCp=skip";
	}

	/**
		Emit a simple Haxe module in the compiler-generated hx dir (bring-up rung).

		Why
		- This approximates “macros generate code that affects typing” without implementing
		  typed AST transforms yet.

		What
		- Emits `Gen.hx` containing `class Gen {}`.
		- Sets `HXHX_HXGEN=1` so the compiler can expose a deterministic effect.
	**/
	public static function genHxModule():String {
		final src = "class Gen {}";
		Compiler.emitHxModule("Gen", src);
		Compiler.define("HXHX_HXGEN", "1");
		return "genHx=ok";
	}

	/**
		Read a compiler define seeded from the compilation CLI (`-D`).

		Why
		- Real-world macros rely on defines for feature flags and target/platform detection.
		- In Stage 4 bring-up we need to prove that:
		  - the compiler can seed a define set
		  - the macro host can query them via `Context.definedValue`
		  - the value roundtrips over the duplex protocol

		What
		- Returns `flag=<value>` for `HXHX_FLAG`.
	**/
	public static function readFlag():String {
		return "flag=" + Context.definedValue("HXHX_FLAG");
	}

	public static function fail():String {
		return MacroError.raise("intentional macro host failure (for position payload tests)");
	}
}
