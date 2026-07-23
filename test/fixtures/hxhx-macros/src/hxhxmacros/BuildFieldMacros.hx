package hxhxmacros;

import hxhxmacrohost.api.Compiler;
import hxhxmacrohost.api.Context;

/**
	Stage4 bring-up build-macro helpers for `hxhx`.

	Why
	- We need a first acceptance rung for `@:build(...)` that does not depend on the full
	  upstream macro interpreter.
	- Stage 4 already has an explicit ABI boundary (compiler ↔ macro host) and a way for
	  macro code to request compiler actions via reverse RPC (`Compiler.*`).

	What
	- `addGeneratedField()` emits a single `generated():String` member into the class/module
	  currently being built, identified by the compiler-provided define:
	  - `HXHX_BUILD_MODULE` (module path, e.g. `demo.Main`)

	How
	- The Stage3 compiler scans for `@:build(...)` metadata, sets `HXHX_BUILD_MODULE`, and then
	  executes this entrypoint inside the macro host.
	- The entrypoint calls `Compiler.emitBuildFields(...)` to send raw Haxe member text back to
	  the compiler, which re-parses and merges it into the module's main class before typing.

	Gotchas
	- This is *not* a real Haxe macro (`#if macro` / `haxe.macro.*`). It's a bring-up model.
	- Keep emitted members within the Stage3 parser/typer subset.
**/
class BuildFieldMacros {
	public static function addGeneratedField():Void {
		final modulePath = Context.definedValue("HXHX_BUILD_MODULE");
		if (modulePath == null || modulePath.length == 0) {
			Compiler.define("HXHX_BUILD_ERROR", "missing_module_path");
			return;
		}

		Compiler.define("HXHX_BUILD_RAN", "1");

		// The two explicit variants let the native server regression prove that
		// macro output can change while the annotated source file stays unchanged.
		// Ordinary fixtures omit the define and retain the established member.
		final variant = Context.definedValue("HXHX_BUILD_VARIANT");
		final members = switch (variant) {
			case "int": "public static function generated_answer():Int return 42;";
			case "int-body": "public static function generated_answer():Int return 43;";
			case "string": 'public static function generated_answer():String return "private-generated-value";';
			case _:
				[
					"public static function generated():Void {",
					'  trace("from_hxhx_build_macro");',
					"}"
				].join("\n");
		};

		Compiler.emitBuildFields(modulePath, members);
	}
}
