package hxhx;

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
	- In the meantime, we gradually grow Stage 1 capabilities behind explicit flags
	  (e.g. parsing via the native frontend seam).
**/
class Main {
	static function main() {
		final args = Sys.args();
		if (args.length == 0) {
			Sys.println("OK hxhx");
			return;
		}

		// Stage 1: internal bring-up flags.
		//
		// These are intentionally separate from the `haxe` CLI surface so we can
		// iterate without breaking compatibility for upstream gate scripts that
		// expect `hxhx` to behave like `haxe`.
		if (args.length >= 1 && args[0] == "--hxhx-parse") {
			if (args.length != 2) {
				Sys.println("Usage: hxhx --hxhx-parse <path/to/File.hx>");
				Sys.exit(1);
			}
			final path = args[1];
			if (!sys.FileSystem.exists(path)) {
				Sys.println("Missing file: " + path);
				Sys.exit(1);
			}
			final src = sys.io.File.getContent(path);
			final decl = ParserStage.parse(src).getDecl();
			Sys.println("parse=ok");
			Sys.println("package=" + (decl.packagePath.length == 0 ? "<none>" : decl.packagePath));
			Sys.println("imports=" + decl.imports.length);
			Sys.println("class=" + decl.mainClass.name);
			Sys.println("hasStaticMain=" + (decl.mainClass.hasStaticMain ? "yes" : "no"));
			return;
		}

		if (args.length == 1 && args[0] == "--hxhx-selftest") {
			CompilerDriver.run();
			Sys.println("OK hxhx selftest");
			return;
		}

		// Compatibility note:
		// `hxhx` is intended to be drop-in compatible with the `haxe` CLI. Some tools (and upstream tests)
		// parse `haxe --version` as a SemVer string, so we must not intercept `--version` here.
		if (args.length == 1 && args[0] == "--hxhx-help") {
			Sys.println("hxhx (stage0 shim + stage1 bring-up)");
			Sys.println("");
			Sys.println("Usage:");
			Sys.println("  hxhx [haxe args...]");
			Sys.println("  hxhx --hxhx-parse <File.hx>");
			Sys.println("  hxhx --hxhx-selftest");
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
