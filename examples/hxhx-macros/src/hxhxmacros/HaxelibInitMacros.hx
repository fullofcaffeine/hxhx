package hxhxmacros;

import haxe.macro.Compiler;
import haxe.macro.Context;

/**
	Stage4 bring-up macro module: library-provided macro initializers (haxelib extra params).

	Why
	- Real Haxe libraries often ship `extraParams.hxml` (or in lix projects, `haxe_libraries/<lib>.hxml`)
	  that includes `--macro SomeInit.init()` lines.
	- Stage3/Stage4 need to support that mechanism so `--library <name>` can “activate” a library’s
	  compile-time behavior without requiring users to manually repeat `--macro ...` on the CLI.

	What
	- `init()` defines `HXHX_HAXELIB_INIT=1`.
	- `scripts/test-hxhx-targets.sh` uses this as a deterministic regression that:
	  - `--library` resolution captures library-provided `--macro` lines, and
	  - Stage3 can execute them when `HXHX_RUN_HAXELIB_MACROS=1` is enabled.

	How
	- In the macro host, `haxe.macro.Compiler.define` is overridden and implemented as a reverse-RPC
	  call back into the compiler process (so the define is visible to conditional compilation and
	  other bring-up diagnostics).
**/
class HaxelibInitMacros {
	public static function init():Void {
		Compiler.define("HXHX_HAXELIB_INIT", "1");

		Context.onAfterTyping(function(_) {
			Compiler.define("HXHX_HAXELIB_INIT_AFTER_TYPING", "1");
		});

		Context.onGenerate(function(_) {
			Compiler.define("HXHX_HAXELIB_INIT_ON_GENERATE", "1");
			Compiler.emitOcamlModule(
				"HxHxHaxelibInitGen",
				"let haxelib_init_generated : int = 1"
			);
		});

		Context.onAfterGenerate(function() {
			Compiler.define("HXHX_HAXELIB_INIT_AFTER_GENERATE", "1");
		});
	}
}
