package hxhx;

import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import hxhx.Stage1Compiler.Stage1Args;

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

	static function hasDefine(args:Array<String>, name:String):Bool {
		return getDefineValue(args, name) != null;
	}

	static function getDefineValue(args:Array<String>, name:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if (a == "-D" && i + 1 < args.length) {
				final d = args[i + 1];
				if (d == name) return "1";
				if (StringTools.startsWith(d, name + "=")) return d.substr((name + "=").length);
				i += 2;
				continue;
			}
			i++;
		}
		return null;
	}

	static function addDefineIfMissing(args:Array<String>, define:String):Void {
		final eq = define.indexOf("=");
		final name = eq == -1 ? define : define.substr(0, eq);
		if (hasDefine(args, name)) return;
		args.push("-D");
		args.push(define);
	}

	static function stripAll(args:Array<String>, flag:String):Array<String> {
		final out = new Array<String>();
		for (a in args) if (a != flag) out.push(a);
		return out;
	}

	static function hasAnyTarget(args:Array<String>):Bool {
		// Not exhaustive; just enough to detect "some real platform was chosen".
		//
		// In `--hxhx-ocaml-interp` mode we primarily care about avoiding the "no target"
		// compiler configuration, which can trigger internal stage0 crashes in upstream
		// workloads (Gate1).
		final targetFlags = [
			"-js", "--js",
			"-lua", "--lua",
			"-python", "--python",
			"-php", "--php",
			"-neko", "--neko",
			"-cpp", "--cpp",
			"-cs", "--cs",
			"-java", "--java",
			"-jvm", "--jvm",
			"-hl", "--hl",
			"-swf", "--swf",
			"-as3", "--as3",
			"-xml", "--xml"
		];
		for (a in args) if (targetFlags.indexOf(a) != -1) return true;
		return false;
	}

	static function findUnsupportedLegacyTarget(args:Array<String>):Null<String> {
		for (a in args) {
			switch (a) {
				case "-swf", "--swf":
					return "flash";
				case "-as3", "--as3":
					return "as3";
				case _:
			}
		}
		return null;
	}

	static function isStrictCliDisallowedFlag(flag:String):Bool {
		if (flag == null || flag.length == 0) return false;
		if (flag == "--target" || flag == "--hxhx-target") return true;
		if (StringTools.startsWith(flag, "--hxhx-") && flag != "--hxhx-strict-cli") return true;
		return false;
	}

	static function validateStrictCliShimArgs(shimArgs:Array<String>):Void {
		for (a in shimArgs) {
			if (isStrictCliDisallowedFlag(a)) {
				fatal("hxhx: strict CLI mode rejects non-upstream flag: " + a
					+ " (remove --hxhx-strict-cli to use hxhx extensions)");
			}
		}
	}

	static function sanitizeName(name:String):String {
		final out = new StringBuf();
		final s = name == null ? "" : name;
		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) // a-z
				|| (c >= 65 && c <= 90) // A-Z
				|| (c >= 48 && c <= 57); // 0-9
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		var r = out.toString();
		if (r.length == 0) r = "ocaml_app";
		if (r.charCodeAt(0) >= 48 && r.charCodeAt(0) <= 57) r = "_" + r;
		return r;
	}

	static function defaultExeName(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		return sanitizeName(base.length > 0 ? base : "ocaml_app").toLowerCase();
	}

	static function absPath(p:String):String {
		if (p == null || p.length == 0) return "";
		try {
			return sys.FileSystem.fullPath(p);
		} catch (_:Dynamic) {
			return p;
		}
	}

	static function rmrf(path:String):Void {
		if (path == null || path.length == 0) return;
		if (!sys.FileSystem.exists(path)) return;
		if (!sys.FileSystem.isDirectory(path)) {
			try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
			return;
		}
		final entries = try sys.FileSystem.readDirectory(path) catch (_:Dynamic) [];
		for (name in entries) {
			if (name == null || name.length == 0) continue;
			rmrf(haxe.io.Path.join([path, name]));
		}
		try sys.FileSystem.deleteDirectory(path) catch (_:Dynamic) {}
	}

	/**
		Emulate upstream `--interp` for the OCaml target by compiling and running a native executable.

		Why
		- Upstream tests frequently use `--interp` as “compile + run right now”.
		- For native targets like OCaml there is no interpreter; the closest equivalent is:
		  `compile → dune build → run produced binary`.
		- During bring-up we want this workflow *even before* `hxhx` becomes a full compiler:
		  the stage0 shim can still compile, and we can validate our OCaml build+run harness.

		What
		- Expands any positional `.hxml` args (including nested `--next` / includes).
		- Removes all `--interp` occurrences from the expanded argument list.
		- Forces `-D ocaml_build=native` and (optionally) overrides `-D ocaml_output=...`.
		- Cleans the output dir best-effort, then invokes stage0 `haxe` to generate the dune project.
		- Runs `dune build` implicitly via the OCaml target’s post-emit step, then executes the produced `.exe`.

		How
		- The expected executable name is derived from the output directory name, matching
		  `reflaxe.ocaml.runtimegen.DuneProjectEmitter.defaultExeName`.
		- This is intentionally a *shim-only* runner: the stage0 dependency is removed later
		  when Gate 1 flips to a non-delegating `hxhx` pipeline.
	**/
	static function runOcamlInterpLike(haxeBin:String, forwarded:Array<String>, outOverride:String):Void {
		// Expand positional `.hxml` args so we can safely rewrite flags like `--interp`.
		final expanded = Stage1Args.expandHxmlArgs(forwarded);
		if (expanded == null) fatal("hxhx: failed to expand .hxml args for ocaml run mode");

		var argv = expanded;

		// Remove upstream `--interp` and emulate it by building + running a native OCaml executable.
		argv = stripAll(argv, "--interp");

		// Reflaxe targets emit via macros (`onAfterGenerate`) instead of a built-in backend.
		//
		// In upstream `--interp` workflows, `.hxml` files may still select a "normal" target
		// (e.g. `--js`) for convenience. When we emulate `--interp` via OCaml, we want:
		//   - stage0 to still typecheck under that platform when needed, but
		//   - NOT to produce any non-OCaml artifacts.
		//
		// `--no-output` achieves that while keeping the command line close to upstream.
		if (argv.indexOf("--no-output") == -1) argv.push("--no-output");

		// Ensure we build to native code.
		addDefineIfMissing(argv, "ocaml_build=native");

		// Ensure output dir is deterministic for this run mode.
		if (outOverride != null && outOverride.length > 0) {
			// Force override.
			argv = argv.copy();
			// Remove any existing ocaml_output define.
			final out2 = new Array<String>();
			var i = 0;
			while (i < argv.length) {
				if (argv[i] == "-D" && i + 1 < argv.length && StringTools.startsWith(argv[i + 1], "ocaml_output=")) {
					i += 2;
					continue;
				}
				out2.push(argv[i]);
				i += 1;
			}
			argv = out2;
			argv.push("-D");
			argv.push("ocaml_output=" + outOverride);
		}

		final outDir = getDefineValue(argv, "ocaml_output");
		if (outDir == null || outDir.length == 0) {
			fatal("hxhx: ocaml run mode requires -D ocaml_output=<dir> (or use --target ocaml preset)");
		}

		// NOTE (Gate1 bring-up):
		// Some upstream workloads trigger internal stage0 compiler failures when invoked in a
		// "no target selected" configuration (even if a custom target will generate output
		// via `onAfterGenerate`).
		//
		// To keep the harness stable, inject a sys-capable dummy platform so the compiler
		// has a concrete backend selected, then disable that backend's output.
		//
		// We use `--neko` because it allows `sys.*` (unlike JS). The emitted Neko output is
		// suppressed via `--no-output`; the actual artifact we care about is the OCaml output
		// produced by `reflaxe.ocaml`.
		if (!hasAnyTarget(argv)) {
			argv = argv.copy();
			argv.push("--neko");
			argv.push(haxe.io.Path.join([outDir, "_hxhx_dummy.n"]));
			if (argv.indexOf("--no-output") == -1) {
				argv.push("--no-output");
			}
		}

		// Clean output dir to avoid stale dune artifacts.
		final outAbs = absPath(outDir);
		try {
			if (sys.FileSystem.exists(outAbs)) {
				rmrf(outAbs);
			}
		} catch (_:Dynamic) {
			// Best-effort: target itself can handle reusing the dir; we mainly want deterministic runs.
		}

		final code = Sys.command(haxeBin, argv);
		if (code != 0) Sys.exit(code);

		final exeName = defaultExeName(outDir);
		final exe = haxe.io.Path.join([outDir, "_build", "default", exeName + ".exe"]);
		if (!sys.FileSystem.exists(exe)) {
			fatal("hxhx: ocaml run mode built successfully, but expected executable missing: " + exe);
		}

		final runCode = Sys.command(exe, []);
		Sys.exit(runCode);
	}

	static function main() {
		final args = Sys.args();
		if (args.length == 0) {
			Sys.println("OK hxhx");
			return;
		}

		// Pass-through: everything after `--` is forwarded; if no `--` exists, forward args as-is.
		// This lets us use: `hxhx -- compile-macro.hxml` while still allowing direct `hxhx compile.hxml`.
		final sep = args.indexOf("--");
		final shimArgs = sep == -1 ? args : args.slice(0, sep);
		// Always allocate a fresh array for `forwarded` so subsequent splice/rewrite steps
		// cannot accidentally mutate `args` (which would break shim-flag parsing).
		//
		// This matters in practice because `hxhx` is compiled by our own OCaml backend,
		// and early bring-up semantics are intentionally conservative about mutability.
		var forwarded = sep == -1 ? args.copy() : args.slice(sep + 1);

		final strictCliMode = shimArgs.indexOf("--hxhx-strict-cli") != -1;
		if (strictCliMode) {
			validateStrictCliShimArgs(shimArgs);
			if (sep == -1) forwarded = stripAll(forwarded, "--hxhx-strict-cli");
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

		// Shim-only run mode: emulate `--interp` by compiling to OCaml native and running the produced binary.
		//
		// Why
		// - `--interp` is a common upstream test convenience flag (Gate 1 uses it).
		// - For native targets (like OCaml), "interpretation" is emulated as: compile → build → run.
		//
		// Non-goal
		// - This does not make `hxhx` a real compiler: it is still a stage0 shim path.
		var ocamlInterpLike = false;
		var ocamlInterpOutDir = "";
		{
			var i = 0;
			while (i < shimArgs.length) {
				switch (shimArgs[i]) {
					case "--hxhx-ocaml-interp":
						ocamlInterpLike = true;
						if (sep == -1) forwarded.splice(i, 1);
						i += 1;
					case "--hxhx-ocaml-out":
						if (i + 1 >= shimArgs.length) fatal("Usage: --hxhx-ocaml-out <dir>");
						ocamlInterpOutDir = shimArgs[i + 1];
						if (sep == -1) forwarded.splice(i, 2);
						i += 2;
					case _:
						i += 1;
				}
			}
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
			final parseDebug = Sys.getEnv("HXHX_PARSE_DEBUG");
			if (parseDebug == "1" || parseDebug == "true" || parseDebug == "yes") {
				try {
					final tail = src.length > 80 ? src.substr(src.length - 80) : src;
					Sys.stderr().writeString("[hxhx parse] len=" + src.length + " tail=" + tail.split("\n").join("\\n") + "\n");
				} catch (_:Dynamic) {}
			}
			final decl = ParserStage.parse(src).getDecl();
			final pkg = HxModuleDecl.getPackagePath(decl);
			final imports = HxModuleDecl.getImports(decl);
			final cls = HxModuleDecl.getMainClass(decl);
			final toplevelMain = HxModuleDecl.getHasToplevelMain(decl);
			Sys.println("parse=ok");
			Sys.println("package=" + (pkg.length == 0 ? "<none>" : pkg));
			Sys.println("imports=" + imports.length);
			Sys.println("class=" + HxClassDecl.getName(cls));
			Sys.println("hasStaticMain=" + (HxClassDecl.getHasStaticMain(cls) ? "yes" : "no"));
			Sys.println("hasToplevelMain=" + (toplevelMain ? "yes" : "no"));
			return;
		}

		if (args.length == 1 && args[0] == "--hxhx-selftest") {
			CompilerDriver.run();
			Sys.println("OK hxhx selftest");
			return;
		}

		// Stage0/builtin target preset selection (`--target`).
		//
		// This is a shim-owned flag family and should never be forwarded to stage0 `haxe`.
		// See `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md:1`.
		{
			// Only parse shim flags in the pre-`--` section (so `hxhx -- --target ...` forwards).
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

				final resolved = try {
					TargetPresets.resolve(targetId, forwarded);
				} catch (e:Dynamic) {
					fatal("hxhx: " + Std.string(e));
				};
				forwarded = resolved.forwarded;

				if (resolved.runMode == TargetPresets.RUN_MODE_BUILTIN_STAGE3) {
					if (ocamlInterpLike) {
						fatal("hxhx: --hxhx-ocaml-interp cannot be combined with --target " + resolved.id);
					}
					final stage3Args = ["--hxhx-backend", resolved.id].concat(forwarded);
					final code = Stage3Compiler.run(stage3Args);
					Sys.exit(code);
				}
			}

			if (shimArgs.length == 1 && shimArgs[0] == "--hxhx-list-targets") {
				for (t in TargetPresets.listTargets()) Sys.println(t);
				return;
			}
		}

		final unsupportedLegacyTarget = findUnsupportedLegacyTarget(forwarded);
		if (unsupportedLegacyTarget != null) {
			fatal('hxhx: Target "' + unsupportedLegacyTarget + '" is not supported in this implementation. Legacy Flash/AS3 targets are intentionally unsupported.');
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
			Sys.println("  hxhx --hxhx-strict-cli [haxe args...]");
			Sys.println("  hxhx --hxhx-parse <File.hx>");
			Sys.println("  hxhx --hxhx-selftest");
			Sys.println("  hxhx --hxhx-list-targets");
			Sys.println("");
			Sys.println("Environment:");
			Sys.println("  HAXE_BIN  Path to stage0 `haxe` (default: haxe)");
			Sys.println("");
			Sys.println("Notes:");
			Sys.println("  - `--version` and `--help` are forwarded to stage0 `haxe` for compatibility.");
			Sys.println("  - `--hxhx-strict-cli` rejects non-upstream flags (e.g. --target, --hxhx-stage3).");
			Sys.println("  - Use `--hxhx-help` for this shim help.");
			return;
		}

		final haxeBin = {
			final v = Sys.getEnv("HAXE_BIN");
			(v == null || v.length == 0) ? "haxe" : v;
		}

		if (ocamlInterpLike) {
			runOcamlInterpLike(haxeBin, forwarded, ocamlInterpOutDir);
			return;
		}

		final code = Sys.command(haxeBin, forwarded);
		Sys.exit(code);
	}
}
