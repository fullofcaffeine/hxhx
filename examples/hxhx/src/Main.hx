/**
	`hxhx` (Haxe-in-Haxe compiler) driver.

	Why this exists:
	- We need a stable CLI surface and an executable that can be built as native OCaml via `reflaxe.ocaml`.
	- Before the real compiler implementation is complete, we can still validate the harness by delegating
	  compilation to a Stage 0 `haxe` binary.

	What it does today:
	- With no args (example harness mode): prints `OK hxhx`.
	- With args: runs Stage 0 `haxe` with the same args, in the same working directory.

	Long-term:
	- The delegation path is removed and `hxhx` becomes the real compiler.
	**/
	class Main {
		static function main() {
			final args = Sys.args();
			if (args.length == 0) {
				Sys.println("OK hxhx");
				return;
			}

			// Compatibility note:
			// `hxhx` is intended to be drop-in compatible with the `haxe` CLI. Some tools (and upstream tests)
			// parse `haxe --version` as a SemVer string, so we must not intercept `--version` here.
			if (args.length == 1 && args[0] == "--hxhx-help") {
				Sys.println("hxhx (stage0 shim)");
				Sys.println("");
				Sys.println("Usage:");
				Sys.println("  hxhx [haxe args...]");
				Sys.println("");
				Sys.println("Environment:");
				Sys.println("  HAXE_BIN  Path to stage0 `haxe` (default: haxe)");
				Sys.println("");
				Sys.println("Notes:");
				Sys.println("  - `--version` and `--help` are forwarded to stage0 `haxe` for compatibility.");
				Sys.println("  - Use `--hxhx-help` for this shim help.");
				return;
			}

			// Pass-through: everything after `--` is forwarded; if no `--` exists, forward args as-is.
			// This lets us use: `hxhx -- compile-macro.hxml` while still allowing direct `hxhx compile.hxml`.
			var forwarded = args;
		final sep = args.indexOf("--");
		if (sep != -1) forwarded = args.slice(sep + 1);

		final haxeBin = {
			final v = Sys.getEnv("HAXE_BIN");
			(v == null || v.length == 0) ? "haxe" : v;
		}

		final code = Sys.command(haxeBin, forwarded);
		Sys.exit(code);
	}
}
