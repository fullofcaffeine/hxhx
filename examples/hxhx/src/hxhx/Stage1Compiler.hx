package hxhx;

/**
	Stage 1 compiler bring-up (`--hxhx-stage1`).

	Why
	- Today `hxhx` is a Stage0 shim: it delegates to an existing `haxe` binary for real compilation.
	- To eventually become a real Haxe-in-Haxe compiler, we need a *non-shim* execution path that
	  can compile something without delegating.
	- The smallest, high-signal slice is `--no-output`: it still exercises CLI parsing, module
	  resolution, and the frontend seam, without forcing us to implement codegen immediately.

	What
	- Implements a minimal subset of the `haxe` CLI:
	  - `-cp <dir>` / `-p <dir>` (repeatable)
	  - `-main <Dotted.TypeName>`
	  - `--no-output`
	- Resolves the main module from classpaths, loads its source, and parses it via `ParserStage`.

	How
	- We intentionally keep the behavior conservative:
	  - unknown flags produce a clear error and non-zero exit code,
	  - missing `--no-output` is rejected (for now),
	  - only the *main module* is parsed (no import/module graph yet).

	Next steps
	- Extend to module graph resolution (imports, `--macro`, `-lib`).
	- Add typing and macro execution model (Gate 1/2 in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md`).
**/
class Stage1Compiler {
	static function error(msg:String):Int {
		Sys.println("hxhx(stage1): " + msg);
		return 2;
	}

	static function formatParseError(e:Dynamic):String {
		// Prefer structured parse errors when available.
		if (Std.isOfType(e, HxParseError)) {
			final pe:HxParseError = cast e;
			return pe.toString();
		}
		return Std.string(e);
	}

	public static function run(args:Array<String>):Int {
		final parsed = Stage1Args.parse(args);
		if (parsed == null) return 2;

		if (!parsed.noOutput) {
			return error("only --no-output is supported in stage1 bring-up");
		}
		if (parsed.main == null || parsed.main.length == 0) {
			return error("missing -main <TypeName>");
		}

		final resolved = Stage1Resolver.resolveMain(parsed.classPaths, parsed.main);
		if (resolved == null) return 2;

		final source = try sys.io.File.getContent(resolved.path) catch (_:Dynamic) null;
		if (source == null) return error("failed to read: " + resolved.path);

		final decl = try {
			ParserStage.parse(source).getDecl();
		} catch (e:Dynamic) {
			return error("parse failed: " + formatParseError(e));
		}
		if (decl.mainClass.name != resolved.className) {
			return error('expected main class "' + resolved.className + '" but parsed "' + decl.mainClass.name + '" in ' + resolved.path);
		}
		if ((decl.packagePath ?? "") != resolved.packagePath) {
			return error('package mismatch for "' + parsed.main + '": expected "' + resolved.packagePath + '" but parsed "' + (decl.packagePath ?? "") + '"');
		}
		if (!decl.mainClass.hasStaticMain) {
			return error('missing "static function main" in ' + parsed.main);
		}

		// Stage1 graph bring-up: parse a small, explicit import closure.
		//
		// This is best-effort and intentionally incomplete:
		// - wildcard imports are ignored
		// - aliases / import modifiers are not supported yet
		for (imp in decl.imports) {
			if (imp == null || imp.length == 0) continue;
			if (StringTools.endsWith(imp, ".*")) {
				Sys.println("stage1=warn import_wildcard " + imp);
				continue;
			}

			final impResolved = Stage1Resolver.resolveModule(parsed.classPaths, imp);
			if (impResolved == null) {
				Sys.println("stage1=warn import_missing " + imp);
				continue;
			}

			final impSrc = try sys.io.File.getContent(impResolved.path) catch (_:Dynamic) null;
			if (impSrc == null) {
				Sys.println("stage1=warn import_unreadable " + impResolved.path);
				continue;
			}

			final impDecl = try {
				ParserStage.parse(impSrc).getDecl();
			} catch (e:Dynamic) {
				return error('parse failed for import "' + imp + '": ' + formatParseError(e));
			}

			if (impDecl.mainClass.name != impResolved.className) {
				Sys.println("stage1=warn import_class_mismatch " + imp);
				continue;
			}
			if ((impDecl.packagePath ?? "") != impResolved.packagePath) {
				Sys.println("stage1=warn import_package_mismatch " + imp);
				continue;
			}
		}

		Sys.println("stage1=ok");
		Sys.println("main=" + parsed.main);
		Sys.println("file=" + resolved.path);
		return 0;
	}
}

/**
	Minimal Stage1 CLI argument parser.

	Why
	- We want stage1 bring-up to be explicit and deterministic: support only a small flag set.
	- This keeps failure modes obvious, and avoids accidental "it sort of worked" behavior.

	What
	- Parses only `-cp/-p`, `-main`, and `--no-output`.
	- Returns `null` (and prints a user-facing message) on invalid input.
**/
class Stage1Args {
	public final classPaths:Array<String>;
	public final main:String;
	public final noOutput:Bool;

	function new(classPaths:Array<String>, main:String, noOutput:Bool) {
		this.classPaths = classPaths;
		this.main = main;
		this.noOutput = noOutput;
	}

	public static function parse(args:Array<String>):Null<Stage1Args> {
		final classPaths = new Array<String>();
		var main = "";
		var noOutput = false;

		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "-cp", "-p":
					if (i + 1 >= args.length) {
						Sys.println("hxhx(stage1): missing value after " + a);
						return null;
					}
					classPaths.push(args[i + 1]);
					i += 2;
				case "-main":
					if (i + 1 >= args.length) {
						Sys.println("hxhx(stage1): missing value after -main");
						return null;
					}
					main = args[i + 1];
					i += 2;
				case "--no-output":
					noOutput = true;
					i += 1;
				case "--":
					// Stage1 never forwards; treat anything after `--` as an error for now.
					Sys.println("hxhx(stage1): unexpected '--' separator");
					return null;
				case _:
					if (StringTools.startsWith(a, "-")) {
						Sys.println("hxhx(stage1): unsupported flag: " + a);
						return null;
					}
					// HXML file arguments are not supported yet.
					Sys.println("hxhx(stage1): unsupported argument: " + a);
					return null;
			}
		}

		if (classPaths.length == 0) classPaths.push(".");
		return new Stage1Args(classPaths, main, noOutput);
	}
}

/**
	Stage1 module resolver (main module only).

	Why
	- Stage1 needs to prove we can resolve modules from `-cp` the way real `haxe` does.
	- Before we implement import graph resolution, resolving just the main entry point gives
	  us a high-value slice with minimal complexity.

	What
	- Given classpaths and a `-main` string (`a.b.Main` or `Main`), finds the first matching
	  `<cp>/a/b/Main.hx` file and returns its path and expected package/class name.

	Gotchas
	- This ignores module aliasing, `--remap`, `-lib` standard classpaths, and `@:build`-induced deps.
	- That is intentional for stage1; those features are added in later tasks.
**/
class Stage1Resolver {
	static inline function normalizeSep(s:String):String {
		return s == null ? "" : StringTools.replace(s, "\\", "/");
	}

	static function joinPath(parts:Array<String>):String {
		var out = "";
		for (p0 in parts) {
			final p = normalizeSep(p0);
			if (p.length == 0) continue;
			if (out.length == 0) {
				out = p;
				continue;
			}
			if (!StringTools.endsWith(out, "/") && !StringTools.startsWith(p, "/")) out += "/";
			else if (StringTools.endsWith(out, "/") && StringTools.startsWith(p, "/")) {
				out += p.substr(1);
				continue;
			}
			out += p;
		}
		return out;
	}

	public static function resolveMain(classPaths:Array<String>, main:String):Null<{
		path:String,
		packagePath:String,
		className:String,
	}> {
		final parts = main.split(".");
		if (parts.length == 0) {
			Sys.println("hxhx(stage1): invalid -main: " + main);
			return null;
		}

		final className = parts[parts.length - 1];
		final pkgParts = parts.slice(0, parts.length - 1);
		final pkg = pkgParts.join(".");

		for (cp in classPaths) {
			final pieces = [cp].concat(pkgParts).concat([className + ".hx"]);
			final candidate = joinPath(pieces);
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) {
				return { path: candidate, packagePath: pkg, className: className };
			}
		}

		Sys.println("hxhx(stage1): could not find main module for -main " + main);
		for (cp in classPaths) Sys.println("  searched: " + normalizeSep(cp));
		return null;
	}

	public static function resolveModule(classPaths:Array<String>, modulePath:String):Null<{
		path:String,
		packagePath:String,
		className:String,
	}> {
		// For now, treat module path and class path as equivalent: `a.b.C` -> `a/b/C.hx`.
		final parts = modulePath.split(".");
		if (parts.length == 0) return null;
		final className = parts[parts.length - 1];
		final pkgParts = parts.slice(0, parts.length - 1);
		final pkg = pkgParts.join(".");

		for (cp in classPaths) {
			final pieces = [cp].concat(pkgParts).concat([className + ".hx"]);
			final candidate = joinPath(pieces);
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) {
				return { path: candidate, packagePath: pkg, className: className };
			}
		}
		return null;
	}
}
