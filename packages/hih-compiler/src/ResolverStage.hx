import haxe.io.Path;

/**
	Stage 2 module resolver skeleton (classpath + transitive import closure).

	Why:
	- A real compiler never sees a single file: it sees a module graph rooted at `-main`.
	- For Haxe-in-Haxe bootstrapping, we need a deterministic, minimal resolver early so
	  typing work has a stable input boundary.
	- This mirrors the same “module closure” idea we validate in `packages/hxhx` Stage 1,
	  but lives *inside* the compiler pipeline we’re incrementally reimplementing in Haxe.

	What:
	- Resolves a `mainModule` (e.g. `demo.A`) to a `.hx` file by searching a list of
	  classpaths (`-cp` roots).
	- Parses the root module and recursively parses its reachable, explicit imports.
	- Ignores wildcard imports (`import a.b.*`) for now (they’re not resolvable without
	  a directory scan + symbol table).
	- Treats missing non-wildcard imports as a hard error (fails fast).

	How:
	- Resolution strategy:
	  1. Try `<cp>/<modulePathWithSlashes>.hx`
	  2. If the import looks like a “subtype in module” (`pack.Mod.SubType`), fall back
	     to `<cp>/pack/Mod.hx` when `<cp>/pack/Mod/SubType.hx` does not exist.
	- Parsing uses `ParserStage.parse`, which can route to either the pure-Haxe frontend
	  or the native OCaml frontend hook (see `ParserStage` hxdoc).
**/
class ResolverStage {
	static function traceResolverDepsEnabled():Bool {
		final v = Sys.getEnv("HXHX_TRACE_RESOLVER_DEPS");
		if (v == null) return false;
		final s = StringTools.trim(v).toLowerCase();
		return s == "1" || s == "true" || s == "yes";
	}

	static function resolveImplicitSamePackageTypesEnabled():Bool {
		final v = Sys.getEnv("HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES");
		// Default-on during bootstrapping.
		//
		// Why
		// - Real Haxe resolves same-package types without explicit imports.
		// - Our resolver is currently syntax-driven (not type-driven), so without this heuristic
		//   we miss dependencies like `Linux.requireAptPackages(...)` in `package runci.targets;`
		//   when `Linux` is referenced without an `import`.
		//
		// Opt-out
		// - Set `HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=0` (or "false"/"no") to disable if it causes
		//   unwanted graph widening.
		if (v == null || StringTools.trim(v).length == 0) return true;
		final s = StringTools.trim(v).toLowerCase();
		if (s == "0" || s == "false" || s == "no") return false;
		return s == "1" || s == "true" || s == "yes";
	}

	static function implicitSamePackageDeps(source:String, modulePath:String, decl:HxModuleDecl):Array<String> {
		final pkg = HxModuleDecl.getPackagePath(decl);
		if (pkg == null || pkg.length == 0) return [];
		final moduleName = modulePath == null ? "" : modulePath.split(".").pop();

		final candidates = new Map<String, Bool>();
		function addMatches(re:EReg):Void {
			var pos = 0;
			while (re.matchSub(source, pos, -1)) {
				final name = re.matched(1);
				if (name != null && name.length > 0) candidates.set(name, true);
				final mp = re.matchedPos();
				pos = mp.pos + mp.len;
			}
		}

		// Note: this is intentionally heuristic. It exists as a bootstrap bridge toward
		// "real typing drives module loading" semantics.
		addMatches(~/\bnew\s+([A-Z][A-Za-z0-9_]*)\b/g);
		addMatches(~/\b([A-Z][A-Za-z0-9_]*)\s*\./g);

		final names = new Array<String>();
		for (name in candidates.keys()) names.push(name);
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		final out = new Array<String>();
		for (name in names) {
			if (name == moduleName) continue;
			out.push(pkg + "." + name);
		}
		return out;
	}

	/**
		Best-effort extractor for fully-qualified type paths referenced directly in expressions.

		Why
		- The bootstrap resolver is still mostly import-driven.
		- Real Haxe code frequently references types without an import, e.g.
		  `haxeserver.HaxeServerSync.launch(...)`.
		- In Stage3 `--hxhx-emit-full-bodies` mode, those references must still pull in the target
		  module, otherwise OCaml link fails with `Unbound module ...`.

		What
		- Scans filtered source for dotted identifiers whose last segment looks like a type name
		  (uppercase-leading), then returns stable-sorted unique candidates.

		Gotchas
		- This is intentionally heuristic and may over-approximate.
		- We only enqueue dependencies that actually resolve on classpaths, which keeps false
		  positives low enough for bring-up.
	**/
	static function implicitQualifiedTypeDeps(source:String):Array<String> {
		if (source == null || source.length == 0) return [];

		final candidates = new Map<String, Bool>();
		// Skip metadata lines (`@:build(...)`, `@:autoBuild(...)`, etc.) so macro entrypoint
		// paths do not widen the main compilation graph.
		for (line in source.split("\n")) {
			final trimmed = StringTools.trim(line);
			if (StringTools.startsWith(trimmed, "@:")) continue;

			final re = ~/\b(([A-Za-z_][A-Za-z0-9_]*\.)+[A-Z][A-Za-z0-9_]*)\b/g;
			var pos = 0;
			while (re.matchSub(line, pos, -1)) {
				final dep = re.matched(1);
				if (dep != null && dep.length > 0) candidates.set(dep, true);
				final mp = re.matchedPos();
				pos = mp.pos + mp.len;
			}
		}

		final out = new Array<String>();
		for (dep in candidates.keys()) out.push(dep);
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	public static function parseProject(classPaths:Array<String>, mainModule:String):Array<ResolvedModule> {
		return parseProjectRoots(classPaths, [mainModule], null);
	}

	/**
		Resolve a project from multiple root modules.

		Why
		- Some macro-time directives (e.g. `--macro include("pack.Mod")`) force additional modules
		  into the compilation universe even when nothing imports them directly.
		- Stage3 bring-up models this as "additional resolver roots" so we can validate that
		  macros can affect the module graph without implementing full DCE/analyzer semantics yet.
	**/
	public static function parseProjectRoots(classPaths:Array<String>, roots:Array<String>, ?defines:haxe.ds.StringMap<String>):Array<ResolvedModule> {
		final out = new Array<ResolvedModule>();
		final visited = new Map<String, Bool>();
		final definesMap = defines == null ? new haxe.ds.StringMap<String>() : defines;

		inline function isMacroStdModule(modulePath:String, filePath:String):Bool {
			if (modulePath != null && StringTools.startsWith(modulePath, "haxe.macro.")) return true;
			if (filePath == null || filePath.length == 0) return false;
			return filePath.indexOf("/haxe/macro/") != -1 || filePath.indexOf("\\haxe\\macro\\") != -1;
		}

		function cloneDefines(src:haxe.ds.StringMap<String>):haxe.ds.StringMap<String> {
			final out = new haxe.ds.StringMap<String>();
			if (src != null) for (k in src.keys()) out.set(k, src.get(k));
			return out;
		}

		final stack = new Array<String>();
		if (roots != null) {
			for (r in roots) {
				if (r == null) continue;
				final m = StringTools.trim(r);
				if (m.length == 0) continue;
				stack.push(m);
			}
		}

		// Use an explicit worklist instead of recursion so widening the module graph (e.g. upstream suites)
		// doesn't risk blowing the OCaml stack during bring-up.
		while (stack.length > 0) {
			final modulePath = stack.pop();
			if (modulePath == null || modulePath.length == 0) continue;
			if (visited.exists(modulePath)) continue;
			visited.set(modulePath, true);

			final filePath = resolveModuleFile(classPaths, modulePath);
			if (filePath == null) throw "import_missing " + modulePath;

			final source = try {
				sys.io.File.getContent(filePath);
			} catch (_:haxe.io.Error) {
				null;
			} catch (_:String) {
				null;
			}
			if (source == null) throw "import_unreadable " + filePath;

			// Apply conditional compilation filtering so inactive `#if` branches don't affect
			// the resolver's module graph during bootstrapping.
			//
			// Macro stdlib note
			// - Haxe's `haxe.macro.*` APIs are only available when compiling the macro context, where
			//   the compiler defines `macro`. The main compilation does not.
			// - Our bootstrap pipeline does not fully separate "macro" vs "main" compilation yet,
			//   but upstream unit harness modules can still reference `haxe.macro.*` at build time.
			// - To keep Gate bring-up moving, parse/filter `haxe.macro.*` modules with `macro=1`
			//   so their declarations exist for Stage3 emission (stubs/Obj.magic are fine here).
			final effectiveDefines = isMacroStdModule(modulePath, filePath)
				? (() -> {
					final m = cloneDefines(definesMap);
					if (!m.exists("macro")) m.set("macro", "1");
					// Macros run on the eval host by default in Haxe 4.x. Many macro APIs are guarded by:
					//   #if (neko || eval || display)
					// so we also set `eval=1` to surface their declarations during bring-up.
					if (!m.exists("eval")) m.set("eval", "1");
					m;
				})()
				: definesMap;
			final filteredSource = HxConditionalCompilation.filterSource(source, effectiveDefines);

			final parsed = try {
				ParserStage.parse(filteredSource, filePath);
			} catch (e:HxParseError) {
				throw "parse_failed " + filePath + ": " + e.message;
			} catch (e:String) {
				throw "parse_failed " + filePath + ": " + e;
			}
			out.push(new ResolvedModule(modulePath, filePath, parsed));

			final decl = parsed.getDecl();
			final modulePkg = HxModuleDecl.getPackagePath(decl);

			final deps = new Array<String>();

			for (rawImport in HxModuleDecl.getImports(decl)) {
				final imp = normalizeImport(rawImport);
				if (imp == null) continue;

				// Haxe import paths can be relative to the current package. In upstream code it's common
				// to write `import MyType` (or `import MyMod.SubType`) inside `package unit;`, which
				// resolves to `unit.MyType` / `unit.MyMod.SubType` if present.
				//
				// Bootstrap rule: try the raw import first, then fall back to a same-package prefix.
				final resolvedImp = {
					final existsDirect = resolveModuleFile(classPaths, imp) != null;
					if (existsDirect) imp else {
						// Only consider a same-package prefix when the import path begins with an uppercase
						// identifier (module/type). Lowercase-leading paths are typically absolute packages
						// (e.g. `haxe.ds.List`) and should not be rewritten.
						final dot = imp.indexOf(".");
						final head = dot == -1 ? imp : imp.substr(0, dot);
						final head0 = head.length == 0 ? 0 : head.charCodeAt(0);
						final headIsUpper = head0 >= "A".code && head0 <= "Z".code;
						if (headIsUpper && modulePkg != null && modulePkg.length > 0 && !StringTools.startsWith(imp, modulePkg + ".")) modulePkg + "." + imp else imp;
					}
				}

				if (StringTools.endsWith(resolvedImp, ".*")) {
					final base = resolvedImp.substr(0, resolvedImp.length - 2);
					// If the base module doesn't exist as a file, treat this as a package-wildcard import
					// (`import pack.*`) and ignore it for graph traversal.
					if (resolveModuleFile(classPaths, base) != null) deps.push(base);
					continue;
				}

				deps.push(resolvedImp);
			}

				// Bootstrap extension: approximate "same-package type resolution" used by the real compiler.
				//
				// IMPORTANT: run the heuristic on the *filtered* source so inactive `#if` branches
				// do not widen the module graph (and accidentally pull in platform-only modules
				// like `unit.TestJava` during `--interp` bring-up).
				final traceDeps = traceResolverDepsEnabled();
				if (resolveImplicitSamePackageTypesEnabled()) {
					for (dep in implicitSamePackageDeps(filteredSource, modulePath, decl)) {
						final exists = resolveModuleFile(classPaths, dep) != null;
						if (traceDeps) Sys.println("resolver_samepkg_dep module=" + modulePath + " dep=" + dep + " exists=" + (exists ? "1" : "0"));
						if (exists) deps.push(dep);
					}
				}

				for (dep in implicitQualifiedTypeDeps(filteredSource)) {
					final exists = resolveModuleFile(classPaths, dep) != null;
					if (traceDeps) Sys.println("resolver_qualified_dep module=" + modulePath + " dep=" + dep + " exists=" + (exists ? "1" : "0"));
					if (exists) deps.push(dep);
				}

			// Preserve the old DFS-ish order by pushing dependencies in reverse.
			var i = deps.length - 1;
			while (i >= 0) {
				final dep = deps[i];
				if (dep != null && dep.length > 0 && !visited.exists(dep)) stack.push(dep);
				i -= 1;
			}
		}
		return out;
	}

	static function normalizeImport(raw:String):Null<String> {
		if (raw == null) return null;
		var s = StringTools.trim(raw);
		if (s.length == 0) return null;

		// Native parser may provide "using Foo" (future-proofing).
		if (StringTools.startsWith(s, "using ")) {
			s = StringTools.trim(s.substr("using ".length));
		}

		// Parser may provide "Foo as Bar"; alias is ignored for resolution.
		final asIdx = s.indexOf(" as ");
		if (asIdx >= 0) s = StringTools.trim(s.substr(0, asIdx));

		return s.length == 0 ? null : s;
	}

	static function resolveModuleFile(classPaths:Array<String>, modulePath:String):Null<String> {
		function fileExistsExactCase(path:String):Bool {
			if (path == null || path.length == 0) return false;
			if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return false;
			final dir = Path.directory(path);
			if (dir == null || dir.length == 0) return true;
			final base = Path.withoutDirectory(path);
			try {
				for (name in sys.FileSystem.readDirectory(dir)) if (name == base) return true;
			} catch (_:haxe.io.Error) {} catch (_:String) {}
			return false;
		}

		final parts = modulePath.split(".");
		if (parts.length == 0) return null;

		final direct = parts.join("/") + ".hx";
		for (cp in classPaths) {
			final candidate = Path.join([cp, direct]);
			if (fileExistsExactCase(candidate)) return candidate;
		}

		// Heuristic: allow import of a type defined in its module file:
		//   import pack.Mod.SubType
		// and fall back to pack/Mod.hx when pack/Mod/SubType.hx doesn't exist.
		if (parts.length >= 2) {
			final fallbackParts = parts.slice(0, parts.length - 1);
			final fallback = fallbackParts.join("/") + ".hx";
			for (cp in classPaths) {
				final candidate = Path.join([cp, fallback]);
				if (fileExistsExactCase(candidate)) return candidate;
			}
		}

		return null;
	}
}
