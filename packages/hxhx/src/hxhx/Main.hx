package hxhx;

import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;

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
	static function fatal<T>(msg:String):T {
		Sys.println(msg);
		Sys.exit(1);
		return cast null;
	}

	static function main() {
		final args = Sys.args();
		if (args.length == 0) {
			Sys.println("OK hxhx");
			return;
		}

		// Stage 4 (bring-up): macro host RPC selftest.
		//
		// This is *not* a user-facing Haxe CLI flag. It exists so CI can validate
		// the ABI boundary early (spawn → handshake → stubbed Context/Compiler call).
		if (args.length == 1 && args[0] == "--hxhx-macro-selftest") {
			try {
				MacroState.reset();
				Sys.println(MacroHostClient.selftest());
				Sys.println("OK hxhx macro rpc");
				return;
			} catch (e:Dynamic) {
				fatal("hxhx: macro selftest failed: " + Std.string(e));
			}
		}

		// Stage 4 (bring-up): invoke a builtin macro entrypoint via RPC.
		//
		// This is still *not* user-facing macro execution. It exists so we can
		// validate the end-to-end request path before we attempt to compile and
		// execute real macro modules.
		if (args.length == 2 && args[0] == "--hxhx-macro-run") {
			try {
				MacroState.reset();
				Sys.println("macro_run=" + MacroHostClient.run(args[1]));
				Sys.println("OK hxhx macro run");
				return;
			} catch (e:Dynamic) {
				fatal("hxhx: macro run failed: " + Std.string(e));
			}
		}

		if (args.length == 2 && args[0] == "--hxhx-macro-get-type") {
			try {
				MacroState.reset();
				Sys.println("macro_getType=" + MacroHostClient.getType(args[1]));
				Sys.println("OK hxhx macro getType");
				return;
			} catch (e:Dynamic) {
				fatal("hxhx: macro getType failed: " + Std.string(e));
			}
		}

		// Stage 1 (bring-up): minimal "non-shim" compilation path.
		//
		// This is explicitly NOT part of the `haxe` CLI surface and will never be forwarded.
		// We grow it incrementally until `hxhx` no longer delegates to stage0 for normal builds.
		if (args.length >= 1 && args[0] == "--hxhx-stage1") {
			final code = Stage1Compiler.run(args.slice(1));
			Sys.exit(code);
		}

		// Stage 3 (bring-up): minimal typed compilation path (no macros).
		//
		// This is explicitly NOT part of the `haxe` CLI surface and will never be forwarded.
		// It exists so we can validate “type → emit → build” without relying on stage0.
		if (args.length >= 1 && args[0] == "--hxhx-stage3") {
			final code = Stage3Compiler.run(args.slice(1));
			Sys.exit(code);
		}

		// Pass-through: everything after `--` is forwarded; if no `--` exists, forward args as-is.
		// This lets us use: `hxhx -- compile-macro.hxml` while still allowing direct `hxhx compile.hxml`.
		var forwarded = args;
		final sep = args.indexOf("--");
		if (sep != -1) forwarded = args.slice(sep + 1);

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
			final pkg = HxModuleDecl.getPackagePath(decl);
			final imports = HxModuleDecl.getImports(decl);
			final cls = HxModuleDecl.getMainClass(decl);
			Sys.println("parse=ok");
			Sys.println("package=" + (pkg.length == 0 ? "<none>" : pkg));
			Sys.println("imports=" + imports.length);
			Sys.println("class=" + HxClassDecl.getName(cls));
			Sys.println("hasStaticMain=" + (HxClassDecl.getHasStaticMain(cls) ? "yes" : "no"));
			return;
		}

		if (args.length == 1 && args[0] == "--hxhx-selftest") {
			CompilerDriver.run();
			Sys.println("OK hxhx selftest");
			return;
		}

		// Stage0 shim ergonomics: bundled/builtin backend selection.
		//
		// This is shim-only and should never be forwarded to stage0 `haxe`.
		// See `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md:1`.
		{
			// Only parse shim flags in the pre-`--` section (so `hxhx -- --target ...` forwards).
			final shimArgs = sep == -1 ? args : args.slice(0, sep);
			final idx = shimArgs.indexOf("--target");
			final idx2 = shimArgs.indexOf("--hxhx-target");
			final i = idx != -1 ? idx : idx2;
			if (i != -1) {
				if (i + 1 >= shimArgs.length) {
					fatal("Usage: hxhx --target <id> [haxe args...]");
				}

				final targetId = shimArgs[i + 1];
				// Remove the shim flag from the forwarded args (only if it was part of the forwarded set).
				if (sep == -1) {
					forwarded = forwarded.copy();
					forwarded.splice(i, 2);
				}
				try forwarded = TargetPresets.apply(targetId, forwarded)
				catch (e:Dynamic) forwarded = fatal("hxhx: " + Std.string(e));
			}

			if (shimArgs.length == 1 && shimArgs[0] == "--hxhx-list-targets") {
				for (t in TargetPresets.listTargets()) Sys.println(t);
				return;
			}
		}

		// Compatibility note:
		// `hxhx` is intended to be drop-in compatible with the `haxe` CLI. Some tools (and upstream tests)
		// parse `haxe --version` as a SemVer string, so we must not intercept `--version` here.
		if (args.length == 1 && args[0] == "--hxhx-help") {
			Sys.println("hxhx (stage0 shim + stage1 bring-up)");
			Sys.println("");
			Sys.println("Usage:");
			Sys.println("  hxhx [haxe args...]");
			Sys.println("  hxhx --target <id> [haxe args...]");
			Sys.println("  hxhx --hxhx-parse <File.hx>");
			Sys.println("  hxhx --hxhx-selftest");
			Sys.println("  hxhx --hxhx-list-targets");
			Sys.println("");
			Sys.println("Environment:");
			Sys.println("  HAXE_BIN  Path to stage0 `haxe` (default: haxe)");
			Sys.println("");
			Sys.println("Notes:");
			Sys.println("  - `--version` and `--help` are forwarded to stage0 `haxe` for compatibility.");
			Sys.println("  - Use `--hxhx-help` for this shim help.");
			return;
		}

		final haxeBin = {
			final v = Sys.getEnv("HAXE_BIN");
			(v == null || v.length == 0) ? "haxe" : v;
		}

		final code = Sys.command(haxeBin, forwarded);
		Sys.exit(code);
	}
}
