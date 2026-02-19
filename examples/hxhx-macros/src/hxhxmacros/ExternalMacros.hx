package hxhxmacros;

import hxhxmacrohost.api.Compiler;
import hxhxmacrohost.api.Context;

/**
	Example “non-builtin” macro module used by Stage 4 bring-up tests.

	Why
	- Stage 4 starts with builtin macro entrypoints compiled into `hxhx-macro-host` for stability.
	- To move toward real-world macro execution (plugins/backends), we also need to prove that the
	  macro host can run macro functions that live *outside* `hxhxmacrohost.BuiltinMacros`.

	What
	- `external()` is a deterministic macro entrypoint that:
	  - reads a define via `Context.definedValue`
	  - sets a define via `Compiler.define`
	  - emits an OCaml module via `Compiler.emitOcamlModule`

	How
	- This module is compiled into the macro host binary during tests by passing an extra `-cp`
	  to the macro host build.
	- The macro host dispatcher recognizes `hxhxmacros.*` expressions of the shape
	  `SomeClass.someMethod()` (no args) and invokes the static method by reflection.
**/
class ExternalMacros {
	public static function external():String {
		final flag = Context.definedValue("HXHX_FLAG");
		Compiler.define("HXHX_EXTERNAL", "1");
		Compiler.emitOcamlModule("HxHxExternal", "let external_flag : string = \"" + flag + "\"");
		return "external=ok";
	}
}
