package hxhx;

import haxe.io.Path;

/**
	Shim-only “target preset” support for `hxhx`.

	Why:
	- Reflaxe-style backends are typically enabled by a *bundle* of flags:
	  `-cp`/`-lib` plus macro init plus target defines (e.g. `-D ocaml_output=...`).
	- That works, but it's verbose and easy to get wrong, especially when we're shipping
	  `hxhx` as a single binary and want a “batteries included” experience.
	- The long-term `hxhx` goal is to become a real compiler. Until then, we still want
	  a **stable CLI surface** for selecting the backend distribution wants to ship.

	What:
	- This class implements a minimal registry for `--target <id>` (and `--hxhx-target <id>`).
	- In Stage0 (shim) mode, the preset works by **injecting** additional `haxe` CLI flags
	  before delegating to the stage0 `haxe` binary.

	How:
	- Injection is intentionally conservative:
	  - additive by default (we only add what is missing),
	  - user flags win (we don't override explicit values),
	  - contradictions fail fast with a clear error.
	- When running from a `dist/hxhx/...` artifact, presets can use bundled library sources
	  located relative to the `hxhx` executable (`../lib/...`) to avoid requiring `haxelib`.
**/
class TargetPresets {
	public static function listTargets():Array<String> {
		// Keep this stable: scripts/docs can rely on it.
		return ["ocaml"];
	}

	public static function apply(targetId:String, forwarded:Array<String>):Array<String> {
		return switch (targetId) {
			case "ocaml": applyOcaml(forwarded);
			case _: throw "Unknown target: " + targetId;
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
		} catch (_:Dynamic) {
			return null;
		}
	}
}

private class ArgScan {
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
}

