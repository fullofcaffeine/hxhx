package hxhxmacrohost.api;

import hxhxmacrohost.MacroRuntime;

/**
	Minimal “Compiler-like” API surface for Stage 4 macro bring-up.

	Why
	- Real Haxe macros talk to `haxe.macro.Compiler` to affect compilation (defines, classpaths, etc.).
	- Stage 4 begins by proving that we can run *some* macro code in-process and make observable
	  changes to macro-host state, without delegating to stage0.

	What
	- Today this only supports `define(name, value)` for the macro-host define store.
	- This is intentionally tiny: it’s the smallest useful “effect” a macro can have.

	How
	- Backed by `MacroRuntime.defines`.
	- Called directly by builtin macro entrypoints (e.g. `hxhxmacrohost.BuiltinMacros.smoke()`).
**/
class Compiler {
	public static function define(name:String, value:String):Void {
		if (name == null || name.length == 0) return;
		MacroRuntime.defines.set(name, value);
	}
}

