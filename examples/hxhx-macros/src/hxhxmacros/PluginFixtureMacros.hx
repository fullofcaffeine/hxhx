package hxhxmacros;

import haxe.macro.Compiler;
import haxe.macro.Context;

/**
	Stage4 fixture “compiler plugin” implemented as a macro library.

	Why
	- For this repo, “plugin system support” primarily means “macro + hook compatibility”.
	  Real targets (e.g. Reflaxe backends) behave like compiler plugins by:
	  - running one or more `--macro ...` initializers, and
	  - registering hooks like `Context.onAfterTyping` / `Context.onGenerate`.
	- We need a deterministic, repo-local fixture that exercises the *ABI boundary* (macro host ↔ compiler)
	  without depending on upstream Haxe sources.

	What
	- `init()` performs three plugin-like effects:
	  1) defines a flag (`HXHX_PLUGIN_FIXTURE=1`)
	  2) optionally injects a classpath (from `HXHX_PLUGIN_FIXTURE_CP`)
	  3) registers `onAfterTyping` and `onGenerate` hooks
	- The `onGenerate` hook emits a tiny OCaml module (`HxHxPluginFixtureGen.ml`) via reverse RPC.

	How
	- `Compiler.define` / `Compiler.addClassPath` are overridden in the Stage4 macro host and lowered to
	  reverse RPC calls back into the compiler process.
	- `Context.onAfterTyping` / `Context.onGenerate` register hook IDs inside the macro host and notify
	  the compiler so it can call them at deterministic points in the Stage3 pipeline.

	Gotchas
	- This fixture is intentionally tiny and avoids complex macro AST work. Its purpose is to validate
	  the “plumbing”: hooks, defines, classpaths, and artifact emission.
**/
class PluginFixtureMacros {
	/**
		Initialize the fixture plugin.

		Environment
		- `HXHX_PLUGIN_FIXTURE_CP` (optional): if set to a directory path, the plugin adds it as a
		  compiler classpath via `Compiler.addClassPath`.
	**/
	public static function init():Void {
		Compiler.define("HXHX_PLUGIN_FIXTURE", "1");

		final cp = Sys.getEnv("HXHX_PLUGIN_FIXTURE_CP");
		if (cp != null && StringTools.trim(cp).length > 0) {
			Compiler.addClassPath(cp);
		}

		Context.onAfterTyping(function(_) {
			Compiler.define("HXHX_PLUGIN_FIXTURE_AFTER_TYPING", "1");
		});

		Context.onGenerate(function(_) {
			Compiler.define("HXHX_PLUGIN_FIXTURE_ON_GENERATE", "1");
			Compiler.emitOcamlModule(
				"HxHxPluginFixtureGen",
				"let plugin_fixture_generated : string = \"ok\""
			);
		});
	}
}

