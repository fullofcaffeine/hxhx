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
	static function resolveImplicitSamePackageTypesEnabled():Bool {
		final v = Sys.getEnv("HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES");
		return v == "1" || v == "true" || v == "yes";
	}

	static function implicitSamePackageDeps(source:String, modulePath:String, decl:HxModuleDecl):Array<String> {
		final pkg = HxModuleDecl.getPackagePath(decl);
		if (pkg == null || pkg.length == 0) return [];
		final moduleName = modulePath == null ? "" : modulePath.split(".").pop();

		final candidates = new Map<String, Bool>();
		function addMatches(re:EReg):Void {
			var pos = 0;
			while (re.matchSub(source, pos)) {
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

	public static function parseProject(classPaths:Array<String>, mainModule:String):Array<ResolvedModule> {
		return parseProjectRoots(classPaths, [mainModule]);
	}

	/**
		Resolve a project from multiple root modules.

		Why
		- Some macro-time directives (e.g. `--macro include("pack.Mod")`) force additional modules
		  into the compilation universe even when nothing imports them directly.
		- Stage3 bring-up models this as "additional resolver roots" so we can validate that
		  macros can affect the module graph without implementing full DCE/analyzer semantics yet.
	**/
	public static function parseProjectRoots(classPaths:Array<String>, roots:Array<String>):Array<ResolvedModule> {
		final out = new Array<ResolvedModule>();
		final visited = new Map<String, Bool>();

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

			final source = try sys.io.File.getContent(filePath) catch (_:Dynamic) null;
			if (source == null) throw "import_unreadable " + filePath;

			final parsed = try ParserStage.parse(source, filePath) catch (e:Dynamic) {
				throw "parse_failed " + filePath + ": " + Std.string(e);
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
			if (resolveImplicitSamePackageTypesEnabled()) {
				for (dep in implicitSamePackageDeps(source, modulePath, decl)) {
					if (resolveModuleFile(classPaths, dep) != null) deps.push(dep);
				}
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
		final parts = modulePath.split(".");
		if (parts.length == 0) return null;

		final direct = parts.join("/") + ".hx";
		for (cp in classPaths) {
			final candidate = Path.join([cp, direct]);
			if (sys.FileSystem.exists(candidate)) return candidate;
		}

		// Heuristic: allow import of a type defined in its module file:
		//   import pack.Mod.SubType
		// and fall back to pack/Mod.hx when pack/Mod/SubType.hx doesn't exist.
		if (parts.length >= 2) {
			final fallbackParts = parts.slice(0, parts.length - 1);
			final fallback = fallbackParts.join("/") + ".hx";
			for (cp in classPaths) {
				final candidate = Path.join([cp, fallback]);
				if (sys.FileSystem.exists(candidate)) return candidate;
			}
		}

		return null;
	}
}
