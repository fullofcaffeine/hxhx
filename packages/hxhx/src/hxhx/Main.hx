package hxhx;

import hxhx.runtime.NullableRuntimeString;
#if !hxhx_stage0_no_external_macro_host
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
#end
#if !hxhx_stage0_no_stage3
import hxhx.Stage3Compiler;
#end
import hxhx.Stage1Compiler.Stage1Args;

private typedef StandardTargetScan = {
	final hasJs:Bool;
	final hasNonJs:Bool;
	final hasLegacy:Bool;
	final missingValueFlag:Null<String>;
}

private typedef RoutePlan = {
	final lane:String;
	final backendId:Null<String>;
	final forwarded:Array<String>;
	final stage0Required:Bool;
}

/**
	`hxhx` (Haxe-in-Haxe compiler) driver.

	Why this exists:
	- We need a stable CLI surface and an executable that can be built as native OCaml via `reflaxe.ocaml`.
	- Before the real compiler implementation is complete, we can still validate the harness by delegating
	  compilation to a Stage 0 `haxe` binary.

	What it does today:
	- With no args (example harness mode): prints `OK hxhx`.
	- With args: resolves shim/native paths first; otherwise delegates to Stage 0 `haxe`.

	Long-term:
	- The delegation path is removed and `hxhx` becomes the real compiler.
	- In the meantime, we gradually grow Stage 1 capabilities behind explicit flags
	  (e.g. parsing via the native frontend seam).
**/
class Main {
	static inline final COMPAT_HAXE_VERSION:String = "4.3.7";
	static inline final LANE_NATIVE_OCAML:String = "native-ocaml";
	static inline final LANE_NATIVE_JS:String = "native-js";
	static inline final LANE_NATIVE_NEKO:String = "native-neko";
	static inline final LANE_NATIVE_HL:String = "native-hl";
	static inline final LANE_NATIVE_CPP:String = "native-cpp";
	static inline final LANE_NATIVE_PYTHON:String = "native-python";
	static inline final LANE_NATIVE_JAVA:String = "native-java";
	static inline final LANE_NATIVE_CS:String = "native-cs";
	static inline final LANE_NATIVE_PHP:String = "native-php";
	static inline final LANE_NATIVE_LUA:String = "native-lua";
	static inline final LANE_STAGE0_COMPAT:String = "stage0-compat";
	static inline final LANE_STAGE0_OCAML_EVAL:String = "stage0-ocaml-eval";

	static function fatal<T>(msg:String):T {
		Sys.println(msg);
		Sys.exit(1);
		return cast null;
	}

	static function isVersionQuery(args:Array<String>):Bool {
		return args.length == 1 && (args[0] == "--version" || args[0] == "-version");
	}

	static function isHelpQuery(args:Array<String>):Bool {
		return args.length == 1 && (args[0] == "--help" || args[0] == "-help" || args[0] == "-h" || args[0] == "--hxhx-help");
	}

	static function printHxhxHelp():Void {
		Sys.println("hxhx Compiler " + COMPAT_HAXE_VERSION + " (compatibility baseline)");
		Sys.println("Usage: hxhx <target> [options] [hxml files and dot paths...]");
		Sys.println("");
		Sys.println("Target:");
		Sys.println("  --ocaml                              compile in native OCaml lane");
		Sys.println("  --ocaml-eval                         compile in delegated OCaml eval lane");
		Sys.println("  -js, --js <file>                     emit JavaScript in native lane");
		Sys.println("  --compat                             delegate to upstream stage0 haxe");
		Sys.println("");
		Sys.println("Core options:");
		Sys.println("  --version                            print compatibility version");
		Sys.println("  --help                               show hxhx supported-surface help");
		Sys.println("  --hxhx-help                          alias for --help");
		Sys.println("  --no-output                          skip target file emission");
		Sys.println("  --cwd <dir>                          run as if in the given directory");
		Sys.println("");
		Sys.println("hxhx options:");
		Sys.println("  --hxhx-list-targets                  list supported hxhx lane selectors");
		Sys.println("  --hxhx-strict-cli                    reject hxhx-only flags");
		Sys.println("  --hxhx-stage3 ...                    run native Stage3 driver directly");
		Sys.println("  --hxhx-customization <id>            enable explicit Stage3 customization");
		Sys.println("  --hxhx-no-emit                       typecheck only in Stage3 lane");
		Sys.println("  --hxhx-no-run                        emit/build without execution");
		Sys.println("  --hxhx-parse <File.hx>               parse a file via native parser seam");
		Sys.println("  --hxhx-selftest                      run internal selftest");
		Sys.println("");
		Sys.println("Plugin commands:");
		Sys.println("  plugin build <dir> [--out-dir <dir>] build a generated native plugin scaffold");
		Sys.println("  plugin test <dir> [--out-dir <dir>]  validate scaffold build/test markers");
		Sys.println("");
		Sys.println("Environment:");
		Sys.println("  HXHX_FORBID_STAGE0=1                 fail on any stage0 delegation path");
		Sys.println("  HAXE_BIN=<path>                      stage0 binary path for delegated flows");
		Sys.println("");
		Sys.println("Notes:");
		Sys.println("  - Removed flags: --target / --hxhx-target.");
		Sys.println("  - Legacy Flash/AS3 targets are intentionally unsupported.");
		Sys.println("  - Use --compat for explicit stage0 delegation.");
	}

	static function hxhxRootDir():String {
		final envRoot = Sys.getEnv("HXHX_ROOT");
		if (envRoot != null && envRoot.length > 0)
			return envRoot;
		return sys.FileSystem.fullPath(".");
	}

	static function repoScriptPath(relPath:String):String {
		final scriptPath = haxe.io.Path.join([hxhxRootDir(), relPath]);
		if (!sys.FileSystem.exists(scriptPath))
			fatal("hxhx: required repo script not found: " + scriptPath + " (set HXHX_ROOT if running outside repo root)");
		return scriptPath;
	}

	static function printPluginHelp():Void {
		Sys.println("Usage:");
		Sys.println("  hxhx plugin build <dir> [--out-dir <dir>]");
		Sys.println("  hxhx plugin test <dir> [--out-dir <dir>]");
		Sys.println("");
		Sys.println("Notes:");
		Sys.println("  - These wrappers are repo-local developer workflows.");
		Sys.println("  - <dir> may be a plugin scaffold root or a direct plugin/hxhx source dir.");
		Sys.println("  - Set HXHX_ROOT when invoking from outside the repo root.");
	}

	static function runRepoScript(scriptRelPath:String, scriptArgs:Array<String>):Void {
		final scriptPath = repoScriptPath(scriptRelPath);
		final code = Sys.command("bash", [scriptPath].concat(scriptArgs));
		Sys.exit(code);
	}

	static function handlePluginCommand(pluginArgs:Array<String>, strictCliMode:Bool):Void {
		if (strictCliMode)
			fatal("hxhx: strict CLI mode rejects non-upstream subcommand: plugin");
		if (pluginArgs.length == 0 || pluginArgs[0] == "--help" || pluginArgs[0] == "-h" || pluginArgs[0] == "help") {
			printPluginHelp();
			return;
		}
		switch (pluginArgs[0]) {
			case "build":
				runRepoScript("scripts/hxhx/plugin-build.sh", pluginArgs.slice(1));
			case "test":
				runRepoScript("scripts/hxhx/plugin-test.sh", pluginArgs.slice(1));
			case _:
				fatal("hxhx: unknown plugin subcommand `" + pluginArgs[0] + "`");
		}
	}

	static function hasDefine(args:Array<String>, name:String):Bool {
		return getDefineValue(args, name) != null;
	}

	static function isTrueEnv(name:String):Bool {
		final raw = NullableRuntimeString.normalize(Sys.getEnv(name));
		if (raw == null)
			return false;
		switch (raw.toLowerCase()) {
			case "1", "true", "yes", "on":
				return true;
			case _:
				return false;
		}
	}

	static function getDefineValue(args:Array<String>, name:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if (a == "-D" && i + 1 < args.length) {
				final d = args[i + 1];
				if (d == name)
					return "1";
				if (StringTools.startsWith(d, name + "="))
					return d.substr((name + "=").length);
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
		if (hasDefine(args, name))
			return;
		args.push("-D");
		args.push(define);
	}

	static function stripAll(args:Array<String>, flag:String):Array<String> {
		final out = new Array<String>();
		for (a in args)
			if (a != flag)
				out.push(a);
		return out;
	}

	static function hasFlag(args:Array<String>, flag:String):Bool {
		return args.indexOf(flag) != -1;
	}

	static function findFlagValue(args:Array<String>, flag:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			if (args[i] == flag) {
				if (i + 1 < args.length)
					return args[i + 1];
				return null;
			}
			i += 1;
		}
		return null;
	}

	static function hasAnyTarget(args:Array<String>):Bool {
		// Not exhaustive; just enough to detect "some real platform was chosen".
		//
		// In `--hxhx-ocaml-interp` mode we primarily care about avoiding the "no target"
		// compiler configuration, which can trigger internal stage0 crashes in upstream
		// workloads (Gate1).
		final targetFlags = [
			    "-js",     "--js",
			   "-lua",    "--lua",
			"-python", "--python",
			   "-php",    "--php",
			  "-neko",   "--neko",
			   "-cpp",    "--cpp",
			    "-cs",     "--cs",
			  "-java",   "--java",
			   "-jvm",    "--jvm",
			    "-hl",     "--hl",
			   "-swf",    "--swf",
			   "-as3",    "--as3",
			   "-xml",    "--xml"
		];
		for (a in args)
			if (targetFlags.indexOf(a) != -1)
				return true;
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

	static function hasStandardJsTargetFlag(args:Array<String>):Bool {
		for (a in args) {
			switch (a) {
				case "-js", "--js":
					return true;
				case _:
			}
		}
		return false;
	}

	static function hasStandardNonJsTargetFlag(args:Array<String>):Bool {
		for (a in args) {
			switch (a) {
				case "-lua", "--lua", "-python", "--python", "-php", "--php", "-neko", "--neko", "-cpp", "--cpp", "-cs", "--cs", "-java", "--java", "-jvm",
					"--jvm", "-hl", "--hl", "-swf", "--swf", "-as3", "--as3", "-xml", "--xml":
					return true;
				case _:
			}
		}
		return false;
	}

	static function shouldRouteStandardJsToNative(forwarded:Array<String>):Bool {
		final expanded = Stage1Args.expandHxmlArgs(forwarded);
		final scan = expanded == null ? forwarded : expanded;
		if (!hasStandardJsTargetFlag(scan))
			return false;
		return !hasStandardNonJsTargetFlag(scan);
	}

	static function isStrictCliDisallowedFlag(flag:String):Bool {
		if (flag == null || flag.length == 0)
			return false;
		if (flag == "--target" || flag == "--hxhx-target")
			return true;
		if (flag == "--ocaml" || flag == "--ocaml-eval" || flag == "--compat")
			return true;
		if (StringTools.startsWith(flag, "--hxhx-") && flag != "--hxhx-strict-cli")
			return true;
		return false;
	}

	static function validateStrictCliShimArgs(shimArgs:Array<String>):Void {
		for (a in shimArgs) {
			if (isStrictCliDisallowedFlag(a)) {
				fatal("hxhx: strict CLI mode rejects non-upstream flag: " + a + " (remove --hxhx-strict-cli to use hxhx extensions)");
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
		if (r.length == 0)
			r = "ocaml_app";
		if (r.charCodeAt(0) >= 48 && r.charCodeAt(0) <= 57)
			r = "_" + r;
		return r;
	}

	static function defaultExeName(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		return sanitizeName(base.length > 0 ? base : "ocaml_app").toLowerCase();
	}

	static function absPath(p:String):String {
		if (p == null || p.length == 0)
			return "";
		try {
			return sys.FileSystem.fullPath(p);
		} catch (_:String) {
			return p;
		}
	}

	static function rmrf(path:String):Void {
		if (path == null || path.length == 0)
			return;
		if (!sys.FileSystem.exists(path))
			return;
		if (!sys.FileSystem.isDirectory(path)) {
			try
				sys.FileSystem.deleteFile(path)
			catch (_:String) {}
			return;
		}
		final entries = try sys.FileSystem.readDirectory(path) catch (_:String) [];
		for (name in entries) {
			if (name == null || name.length == 0)
				continue;
			rmrf(haxe.io.Path.join([path, name]));
		}
		try
			sys.FileSystem.deleteDirectory(path)
		catch (_:String) {}
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
	#if !hxhx_stage0_no_internal_tools
	static function runOcamlInterpLike(haxeBin:String, forwarded:Array<String>, outOverride:String):Void {
		// Expand positional `.hxml` args so we can safely rewrite flags like `--interp`.
		final expanded = Stage1Args.expandHxmlArgs(forwarded);
		if (expanded == null)
			fatal("hxhx: failed to expand .hxml args for ocaml run mode");

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
		if (argv.indexOf("--no-output") == -1)
			argv.push("--no-output");

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
			fatal("hxhx: ocaml run mode requires -D ocaml_output=<dir> (or use --ocaml)");
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
		} catch (_:String) {
			// Best-effort: target itself can handle reusing the dir; we mainly want deterministic runs.
		}

		final code = Sys.command(haxeBin, argv);
		if (code != 0)
			Sys.exit(code);

		final exeName = defaultExeName(outDir);
		final exe = haxe.io.Path.join([outDir, "_build", "default", exeName + ".exe"]);
		if (!sys.FileSystem.exists(exe)) {
			fatal("hxhx: ocaml run mode built successfully, but expected executable missing: " + exe);
		}

		final runCode = Sys.command(exe, []);
		Sys.exit(runCode);
	}
	#end

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
			if (sep == -1)
				forwarded = stripAll(forwarded, "--hxhx-strict-cli");
		}

		if (args.length >= 1 && args[0] == "plugin") {
			handlePluginCommand(args.slice(1), strictCliMode);
			return;
		}

		// Stage 4 (bring-up): macro host RPC selftest.
		//
		// This is *not* a user-facing Haxe CLI flag. It exists so CI can validate
		// the ABI boundary early (spawn → handshake → stubbed Context/Compiler call).
		#if !hxhx_stage0_no_external_macro_host
		if (args.length == 1 && args[0] == "--hxhx-macro-selftest") {
			try {
				MacroState.reset();
				Sys.println(MacroHostClient.selftest());
				Sys.println("OK hxhx macro rpc");
				return;
			} catch (e:String) {
				fatal("hxhx: macro selftest failed: " + e);
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
			} catch (e:String) {
				fatal("hxhx: macro run failed: " + e);
			}
		}

		if (args.length == 2 && args[0] == "--hxhx-macro-get-type") {
			try {
				MacroState.reset();
				Sys.println("macro_getType=" + MacroHostClient.getType(args[1]));
				Sys.println("OK hxhx macro getType");
				return;
			} catch (e:String) {
				fatal("hxhx: macro getType failed: " + e);
			}
		}
		#end

		// Stage 1 (bring-up): minimal "non-shim" compilation path.
		//
		// This is explicitly NOT part of the `haxe` CLI surface and will never be forwarded.
		// We grow it incrementally until `hxhx` no longer delegates to stage0 for normal builds.
		#if !hxhx_stage0_no_internal_tools
		if (args.length >= 1 && args[0] == "--hxhx-stage1") {
			final code = Stage1Compiler.run(args.slice(1));
			Sys.exit(code);
		}
		#end

		// Stage 3 (bring-up): minimal typed compilation path (no macros).
		//
		// This is explicitly NOT part of the `haxe` CLI surface and will never be forwarded.
		// It exists so we can validate “type → emit → build” without relying on stage0.
		if (args.length >= 1 && args[0] == "--hxhx-stage3") {
			#if hxhx_stage0_no_stage3
			fatal("hxhx: --hxhx-stage3 unavailable in stage0 no-stage3 profiling lane");
			#else
			final code = Stage3Compiler.run(args.slice(1));
			Sys.exit(code);
			#end
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
		#if !hxhx_stage0_no_internal_tools
		{
			var i = 0;
			while (i < shimArgs.length) {
				switch (shimArgs[i]) {
					case "--hxhx-ocaml-interp":
						ocamlInterpLike = true;
						if (sep == -1)
							forwarded.splice(i, 1);
						i += 1;
					case "--hxhx-ocaml-out":
						if (i + 1 >= shimArgs.length)
							fatal("Usage: --hxhx-ocaml-out <dir>");
						ocamlInterpOutDir = shimArgs[i + 1];
						if (sep == -1)
							forwarded.splice(i, 2);
						i += 2;
					case _:
						i += 1;
				}
			}
		}
		#end

		// Stage 1: internal bring-up flags.
		//
		// These are intentionally separate from the `haxe` CLI surface so we can
		// iterate without breaking compatibility for upstream gate scripts that
		// expect `hxhx` to behave like `haxe`.
		#if !hxhx_stage0_no_internal_tools
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
				} catch (_:haxe.io.Error) {} catch (_:String) {}
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
		#end

		// Compatibility note:
		// `hxhx` is intended to be drop-in compatible with the `haxe` CLI.
		// Many tools parse `haxe --version` as SemVer, so this shim must keep
		// version output stable and stage0-free.
		if (isVersionQuery(forwarded)) {
			Sys.println(COMPAT_HAXE_VERSION);
			return;
		}

		if (isHelpQuery(args)) {
			printHxhxHelp();
			return;
		}

		if (shimArgs.length == 1 && shimArgs[0] == "--hxhx-list-targets") {
			for (lane in CliRouting.listLaneSelectors())
				Sys.println(lane);
			return;
		}

		final haxeBin = {
			final v = Sys.getEnv("HAXE_BIN");
			(v == null || v.length == 0) ? "haxe" : v;
		}
		final forbidStage0Delegation = isTrueEnv("HXHX_FORBID_STAGE0");

		if (ocamlInterpLike) {
			#if hxhx_stage0_no_internal_tools
			fatal("hxhx: --hxhx-ocaml-interp unavailable in stage0 no-internal-tools profiling lane");
			#end
			if (forbidStage0Delegation) {
				fatal("hxhx: HXHX_FORBID_STAGE0=1 forbids --hxhx-ocaml-interp because this path delegates to stage0 `haxe`.");
			}
			#if !hxhx_stage0_no_internal_tools
			runOcamlInterpLike(haxeBin, forwarded, ocamlInterpOutDir);
			#end
			return;
		}

		final plan = try {
			CliRouting.plan(shimArgs, forwarded);
		} catch (e:String) {
			fatal("hxhx: " + e);
		}
		if (isTrueEnv("HXHX_TRACE_BACKEND_SELECTION")) {
			Sys.println("route_lane=" + plan.lane);
			if (plan.backendId != null)
				Sys.println("route_backend_id=" + plan.backendId);
			if (plan.stage0Required)
				Sys.println("stage0_haxe_bin=" + haxeBin);
		}

		switch (plan.lane) {
			case LANE_NATIVE_OCAML | LANE_NATIVE_JS | LANE_NATIVE_NEKO | LANE_NATIVE_HL | LANE_NATIVE_CPP | LANE_NATIVE_PYTHON | LANE_NATIVE_JAVA |
				LANE_NATIVE_CS | LANE_NATIVE_PHP | LANE_NATIVE_LUA:
				if (ocamlInterpLike) {
					fatal("hxhx: --hxhx-ocaml-interp cannot be combined with native target lanes.");
				}
				#if hxhx_stage0_no_stage3
				fatal("hxhx: native target lanes unavailable in stage0 no-stage3 profiling lane");
				#else
				final stage3Args = ["--hxhx-backend", plan.backendId].concat(plan.forwarded);
				final code = Stage3Compiler.run(stage3Args);
				Sys.exit(code);
				#end
			case LANE_STAGE0_OCAML_EVAL:
				if (forbidStage0Delegation)
					fatal("hxhx: stage0 forbidden; --ocaml-eval requires stage0.");
				final code = Sys.command(haxeBin, plan.forwarded);
				Sys.exit(code);
			case LANE_STAGE0_COMPAT:
				if (forbidStage0Delegation)
					fatal("hxhx: HXHX_FORBID_STAGE0=1 forbids --compat because this path delegates to stage0 `haxe`.");
				final code = Sys.command(haxeBin, plan.forwarded);
				Sys.exit(code);
			case _:
				fatal("hxhx: internal error: unknown route lane " + plan.lane);
		}
	}
}
