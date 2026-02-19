package hxhx;

import backend.BackendRegistry;
import haxe.io.Path;

typedef ResolvedTarget = {
	final id:String;
	final kind:String;
	final runMode:String;
	final describe:String;
	final forwarded:Array<String>;
};

/**
	Shim-only and builtin target preset support for `hxhx`.

	Why:
	- Reflaxe-style backends are typically enabled by a *bundle* of flags:
	  `-cp`/`-lib` plus macro init plus target defines (e.g. `-D ocaml_output=...`).
	- That works, but it's verbose and easy to get wrong, especially when we're shipping
	  `hxhx` as a single binary and want a "batteries included" experience.
	- The long-term `hxhx` goal is to become a real compiler. Until then, we still want
	  a **stable CLI surface** for selecting the backend distribution wants to ship.

	What:
	- This class implements a minimal registry for `--target <id>` (and `--hxhx-target <id>`).
	- Targets can resolve to one of two run modes:
	  - `delegate_stage0`: inject args and forward to stage0 `haxe`.
	  - `builtin_stage3`: run the linked Stage3 backend directly.

	How:
	- Injection is intentionally conservative:
	  - additive by default (we only add what is missing),
	  - user flags win (we don't override explicit values),
	  - contradictions fail fast with a clear error.
	- When running from a `dist/hxhx/...` artifact, presets can use bundled library sources
	  located relative to the `hxhx` executable (`../lib/...`) to avoid requiring `haxelib`.
**/
class TargetPresets {
	public static inline var RUN_MODE_DELEGATE_STAGE0 = "delegate_stage0";
	public static inline var RUN_MODE_BUILTIN_STAGE3 = "builtin_stage3";

	public static function listTargets():Array<String> {
		// Keep this stable: scripts/docs can rely on it.
		return ["ocaml", "ocaml-stage3", "js", "js-native"];
	}

	/**
		Resolve a target preset into an executable plan.

		Why
		- Stage0-friendly targets and linked builtin targets need different execution paths.
		- We keep one stable `--target` UX while allowing the runner to choose:
		  - delegate to stage0 (`delegate_stage0`), or
		  - run a builtin backend directly (`builtin_stage3`).

		What
		- Returns a full target plan:
		  - `kind`: `bundled` / `builtin` / `both`
		  - `runMode`: execution strategy
		  - `forwarded`: CLI args after target-specific injection/normalization
		  - metadata fields for diagnostics/docs
	**/
	public static function resolve(targetId:String, forwarded:Array<String>):ResolvedTarget {
		final normalizedId = targetId == null ? "" : targetId.toLowerCase();
		return switch (normalizedId) {
			case "ocaml": {
				id: "ocaml",
				kind: "both",
				runMode: RUN_MODE_DELEGATE_STAGE0,
				describe: "Reflaxe OCaml backend via stage0 delegation",
				forwarded: applyOcaml(forwarded)
			};
			case "ocaml-stage3":
				ensureBuiltinBackendRegistered("ocaml-stage3");
				{
					id: "ocaml-stage3",
					kind: "builtin",
					runMode: RUN_MODE_BUILTIN_STAGE3,
					describe: "Linked Stage3 OCaml emitter fast-path (no --library required)",
					forwarded: applyOcamlStage3(forwarded)
				};
			case "js": {
				id: "js",
				kind: "bundled",
				runMode: RUN_MODE_DELEGATE_STAGE0,
				describe: "JavaScript target via stage0 delegation",
				forwarded: applyJs(forwarded)
			};
			case "js-native":
				ensureBuiltinBackendRegistered("js-native");
				{
					id: "js-native",
					kind: "builtin",
					runMode: RUN_MODE_BUILTIN_STAGE3,
					describe: "Linked Stage3 JS backend fast-path (non-delegating MVP)",
					forwarded: applyJsNative(forwarded)
				};
			case "flash", "swf", "as3":
				throw unsupportedLegacyTargetMessage(normalizedId);
			case _:
				throw "Unknown target: " + targetId + " (run --hxhx-list-targets for supported presets)";
		}
	}

	public static function apply(targetId:String, forwarded:Array<String>):Array<String> {
		return resolve(targetId, forwarded).forwarded;
	}

	static function unsupportedLegacyTargetMessage(targetId:String):String {
		return 'Target "' + targetId + '" is not supported in hxhx. Legacy Flash/AS3 targets are intentionally unsupported in this implementation.';
	}

	static function ensureBuiltinBackendRegistered(targetId:String):Void {
		if (BackendRegistry.descriptorForTarget(targetId) == null) {
			throw 'Target "' + targetId + '" is not available in this hxhx build (missing builtin backend registration).';
		}
	}

	static function applyOcaml(forwarded:Array<String>):Array<String> {
		final out = forwarded.copy();

		// Contradictions: if the user explicitly selects a different reflaxe target,
		// refuse to guess.
		final reflaxeTarget = ArgScan.getDefineValue(out, "reflaxe-target");
		if (reflaxeTarget != null && reflaxeTarget != "ocaml") {
			throw "Contradiction: --target ocaml but -D reflaxe-target=" + reflaxeTarget;
		}

		// Ensure the backend is enabled (one of):
		// - `-lib reflaxe.ocaml` (typical dev usage)
		// - `--macro reflaxe.ocaml.CompilerInit.Start()` (when injecting classpaths directly)
		final hasLib = ArgScan.hasLib(out, "reflaxe.ocaml");
		final hasInitMacro = ArgScan.hasMacro(out, "reflaxe.ocaml.CompilerInit.Start()");

		if (!hasLib && !hasInitMacro) {
			final bundled = findBundledLibRoot();
			if (bundled != null) {
				// Bundled mode: inject sources directly so the dist artifact is self-contained.
				//
				// We still need the core reflaxe macro entrypoint, plus our target init macro.
				// This mirrors what `-lib reflaxe` and `-lib reflaxe.ocaml` do, without requiring
				// a haxelib database.
				final reflaxeRoot = Path.join([bundled, "reflaxe"]);
				final ocamlRoot = Path.join([bundled, "reflaxe.ocaml"]);

				ArgScan.addCpIfExists(out, Path.join([reflaxeRoot, "src"]));
				ArgScan.addCpIfExists(out, Path.join([ocamlRoot, "src"]));

				ArgScan.addMacroIfMissing(out, 'nullSafety("reflaxe")');
				ArgScan.addMacroIfMissing(out, "reflaxe.ReflectCompiler.Start()");
				ArgScan.addMacroIfMissing(out, "reflaxe.ocaml.CompilerInit.Start()");
			} else {
				// Non-bundled mode: rely on stage0 haxe resolving `-lib` as usual.
				out.unshift("reflaxe.ocaml");
				out.unshift("-lib");
			}
		}

		// Ensure output define exists: reflaxe.ocaml requires it to enable the compiler.
		if (!ArgScan.hasDefine(out, "ocaml_output")) {
			out.push("-D");
			out.push("ocaml_output=out");
		}

		// Helpful hint defines (additive, non-authoritative).
		// These are the “target wiring” defines most projects want anyway.
		ArgScan.addDefineIfMissing(out, "reflaxe-target=ocaml");
		ArgScan.addDefineIfMissing(out, "reflaxe-target-code-injection=ocaml");
		ArgScan.addDefineIfMissing(out, "retain-untyped-meta");

		return out;
	}

	/**
		Normalize args for the linked Stage3 OCaml backend.

		Why
		- `ocaml-stage3` is the first builtin fast-path: we run `Stage3Compiler` directly,
		  so a classpath `--library reflaxe.ocaml` lookup is unnecessary and can fail on hosts
		  without the library installed.

		What
		- Keeps user intent additive and deterministic:
		  - rejects conflicting explicit target defines,
		  - strips only `reflaxe.ocaml` library wiring flags/macros,
		  - preserves all other user-provided flags.
	**/
	static function applyOcamlStage3(forwarded:Array<String>):Array<String> {
		final out = forwarded.copy();

		final reflaxeTarget = ArgScan.getDefineValue(out, "reflaxe-target");
		if (reflaxeTarget != null && reflaxeTarget != "ocaml") {
			throw "Contradiction: --target ocaml-stage3 but -D reflaxe-target=" + reflaxeTarget;
		}

		ArgScan.stripLib(out, "reflaxe.ocaml");
		ArgScan.stripMacro(out, "reflaxe.ocaml.CompilerInit.Start()");
		ArgScan.stripMacro(out, "reflaxe.ReflectCompiler.Start()");
		ArgScan.stripMacro(out, 'nullSafety("reflaxe")');

		return out;
	}

	/**
		Normalize args for delegated JS target selection.

		Why
		- `--target js` should be a convenient preset, but must not silently conflict with
		  explicit non-JS target flags.
		- For compilation runs without an explicit target output, upstream `haxe` requires a
		  concrete target flag, so we provide a deterministic default output path.

		What
		- Fails fast on contradictory explicit target flags.
		- Adds `--js out.js` only when:
		  - no explicit target was selected, and
		  - caller did not request `--no-output` / `--hxhx-no-emit`.
	**/
	static function applyJs(forwarded:Array<String>):Array<String> {
		final out = forwarded.copy();
		final explicitTargets = ArgScan.listExplicitTargets(out);
		for (target in explicitTargets) {
			if (target != "js") {
				throw "Contradiction: --target js but explicit target flag selects " + target;
			}
		}
		if (explicitTargets.length == 0 && !ArgScan.hasNoOutputLike(out)) {
			out.push("--js");
			out.push("out.js");
		}
		return out;
	}

	/**
		Normalize args for the linked Stage3 JS backend.

		Why
		- `js-native` is a builtin Stage3 target path. We still enforce the same contradiction
		  checks and deterministic default output behavior as delegated `--target js`.
		- We seed `-D js-es=5` as the default compatibility baseline unless the user already
		  provided an explicit `js-es` define.

		What
		- Applies JS target normalization.
		- Adds `-D js-es=5` when missing.
	**/
	static function applyJsNative(forwarded:Array<String>):Array<String> {
		final out = applyJs(forwarded);
		ArgScan.addDefineIfMissing(out, "js-es=5");
		return out;
	}

	/**
		Attempt to locate a bundled lib root for dist artifacts.

		Expected dist layout:
		- `<root>/bin/hxhx`
		- `<root>/lib/reflaxe/`
		- `<root>/lib/reflaxe.ocaml/`

		Returns:
		- `<root>/lib` if it looks valid, otherwise `null`.
	**/
	static function findBundledLibRoot():Null<String> {
		try {
			final exe = Sys.programPath();
			if (exe == null || exe.length == 0) return null;
			final abs = sys.FileSystem.fullPath(exe);
			final root = Path.directory(Path.directory(abs)); // <root>/bin/...
			final libRoot = Path.join([root, "lib"]);
			if (!sys.FileSystem.exists(Path.join([libRoot, "reflaxe", "src"]))) return null;
			if (!sys.FileSystem.exists(Path.join([libRoot, "reflaxe.ocaml", "src"]))) return null;
			return libRoot;
		} catch (_:String) {
			return null;
		}
	}
}

private class ArgScan {
	public static function hasNoOutputLike(args:Array<String>):Bool {
		return args.indexOf("--no-output") != -1 || args.indexOf("--hxhx-no-emit") != -1;
	}

	public static function hasTargetFlag(args:Array<String>, targetId:String):Bool {
		final desired = targetId == null ? "" : targetId;
		return firstExplicitTarget(args) == desired;
	}

	public static function firstExplicitTarget(args:Array<String>):Null<String> {
		final all = listExplicitTargets(args);
		return all.length == 0 ? null : all[0];
	}

	public static function listExplicitTargets(args:Array<String>):Array<String> {
		final out = new Array<String>();
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "-js", "--js":
					out.push("js");
				case "-lua", "--lua":
					out.push("lua");
				case "-python", "--python":
					out.push("python");
				case "-php", "--php":
					out.push("php");
				case "-neko", "--neko":
					out.push("neko");
				case "-cpp", "--cpp":
					out.push("cpp");
				case "-cs", "--cs":
					out.push("cs");
				case "-java", "--java":
					out.push("java");
				case "-jvm", "--jvm":
					out.push("jvm");
				case "-hl", "--hl":
					out.push("hl");
				case "-swf", "--swf":
					out.push("swf");
				case "-as3", "--as3":
					out.push("as3");
				case "-xml", "--xml":
					out.push("xml");
				case "--interp":
					out.push("interp");
				case "--run":
					out.push("run");
				case _:
			}
			i += consumesValue(a) ? 2 : 1;
		}
		return out;
	}

	static function consumesValue(flag:String):Bool {
		return switch (flag) {
			case "-js" | "--js" | "-lua" | "--lua" | "-python" | "--python" | "-php" | "--php" | "-neko" | "--neko" | "-cpp" | "--cpp" | "-cs" | "--cs" | "-java" | "--java" | "-jvm" | "--jvm" | "-hl" | "--hl" | "-swf"
				| "--swf" | "-as3" | "--as3" | "-xml" | "--xml" | "--run":
				true;
			case _:
				false;
		}
	}

	public static function hasLib(args:Array<String>, name:String):Bool {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if ((a == "-lib" || a == "--library") && i + 1 < args.length && args[i + 1] == name) return true;
			i++;
		}
		return false;
	}

	public static function hasMacro(args:Array<String>, macroExpr:String):Bool {
		var i = 0;
		while (i < args.length) {
			if (args[i] == "--macro" && i + 1 < args.length && args[i + 1] == macroExpr) return true;
			i++;
		}
		return false;
	}

	public static function addMacroIfMissing(args:Array<String>, macroExpr:String):Void {
		if (hasMacro(args, macroExpr)) return;
		args.push("--macro");
		args.push(macroExpr);
	}

	public static function hasDefine(args:Array<String>, name:String):Bool {
		return getDefineValue(args, name) != null;
	}

	public static function addDefineIfMissing(args:Array<String>, define:String):Void {
		final eq = define.indexOf("=");
		final name = eq == -1 ? define : define.substr(0, eq);
		if (hasDefine(args, name)) return;
		args.push("-D");
		args.push(define);
	}

	public static function getDefineValue(args:Array<String>, name:String):Null<String> {
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

	public static function addCpIfExists(args:Array<String>, path:String):Void {
		if (!sys.FileSystem.exists(path)) return;
		// Don't spam duplicates: classpaths can be long and order-sensitive.
		if (args.indexOf(path) != -1) return;
		args.push("-cp");
		args.push(path);
	}

	public static function stripLib(args:Array<String>, name:String):Void {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if ((a == "-lib" || a == "--library") && i + 1 < args.length && args[i + 1] == name) {
				args.splice(i, 2);
				continue;
			}
			i++;
		}
	}

	public static function stripMacro(args:Array<String>, macroExpr:String):Void {
		var i = 0;
		while (i < args.length) {
			if (args[i] == "--macro" && i + 1 < args.length && args[i + 1] == macroExpr) {
				args.splice(i, 2);
				continue;
			}
			i++;
		}
	}
}
