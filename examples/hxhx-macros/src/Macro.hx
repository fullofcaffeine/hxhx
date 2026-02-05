/**
	CI-friendly stand-in for upstream `tests/unit/src/Macro.hx`.

	Why
	- `scripts/test-hxhx-targets.sh` needs a deterministic `--macro Macro.init()` call to
	  validate the Stage 4 macro host integration (RPC + hook registration).
	- Depending on an untracked `vendor/haxe` checkout for this single macro makes `npm test`
	  fragile in clean clones and in CI jobs that intentionally avoid fetching upstream sources.

	What
	- Provides `Macro.init()` that registers a `Context.onGenerate` hook.
	- The hook is intentionally a no-op; we only need to prove the ABI boundary and hook
	  lifecycle are wired up.

	How
	- Uses `haxe.macro.Context` (implemented/stubbed for the macro host in this repo).
**/
class Macro {
	public static function init():Void {
		haxe.macro.Context.onGenerate(function(_) {});
	}
}

