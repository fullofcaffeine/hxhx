private typedef MissingTypeHook = {
	function invoke(modulePath:String):Bool;
}

/**
	Stage3 module loader: type-driven, on-demand module parsing and indexing.

	Why
	- Stage2/Stage3 resolution currently builds a module graph by following explicit imports.
	  That is insufficient for real-world Haxe, where unimported types can still be resolved via:
	  - same-package lookup (`package p; class Main { static function main() new Util(); }`)
	  - fully-qualified type paths used directly (`new p.Util()`)
	- Upstream’s compiler loads modules lazily: typing drives which modules enter the cache.
	- For Gate1 bring-up, we want to replace brittle “same package scan” heuristics with a
	  deterministic, type-driven loader that can be exercised via tests.

	What
	- Given:
	  - a set of classpaths,
	  - a `defines` map (for conditional compilation filtering),
	  - and a shared `TyperIndex`,
	  this loader can:
	  - resolve a *module path* to a `.hx` file,
	  - parse it (via `ParserStage`),
	  - insert its class signature into the `TyperIndex`,
	  - and expose newly-loaded `ResolvedModule` values to the Stage3 driver.

	How
	- This loader is intentionally conservative:
	  - It only attempts candidate module paths that are derivable from the current typing context
		(fully-qualified, explicit imports, same-package).
	  - It is cycle-safe via a `visited` set keyed by module path.
	  - It applies `HxConditionalCompilation.filterSource` before parsing so inactive branches
		don’t spuriously pull modules into the compilation.

	Gotchas
	- Stage3 indexes every type surfaced by the bootstrap parser/scanners, but it
	  still does not model the complete upstream module/type-resolution contract.
**/
class ModuleLoader extends LazyTypeLoader {
	final classPaths:Array<String>;
	final defines:haxe.ds.StringMap<String>;
	final index:TyperIndex;
	final onMissingType:Null<MissingTypeHook>;
	final sourceProvider:CompilerSourceProvider;

	/**
		Whether lazily loaded modules should recursively pull their direct dependencies.

		Why
		- Real emit lanes need dependency expansion so generated OCaml has every referenced unit.
		- No-emit parity lanes only need the modules demanded by typing, so recursive link-safety
		  expansion is avoidable compiler latency.
	**/
	final expandDependencies:Bool;

	// Module-path based cycle/dup guard.
	final visited:haxe.ds.StringMap<Bool>;
	final typeNotFoundTried:haxe.ds.StringMap<Bool>;

	// Newly loaded modules (drained by the Stage3 driver).
	final pending:Array<ResolvedModule>;

	public function new(classPaths:Array<String>, defines:haxe.ds.StringMap<String>, index:TyperIndex, ?onMissingType:String->Bool,
			?expandDependencies:Bool = true, ?sourceProvider:CompilerSourceProvider) {
		super();
		this.classPaths = classPaths == null ? [] : classPaths;
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.index = index;
		this.onMissingType = onMissingType == null ? null : {invoke: onMissingType};
		this.expandDependencies = expandDependencies;
		this.sourceProvider = sourceProvider == null ? new CompilerSourceProvider() : sourceProvider;
		this.visited = new haxe.ds.StringMap<Bool>();
		this.typeNotFoundTried = new haxe.ds.StringMap<Bool>();
		this.pending = [];
	}

	inline function invokeOnMissingType(mp:String):Bool {
		return onMissingType == null ? false : onMissingType.invoke(mp);
	}

	public function markResolvedAlready(resolved:Array<ResolvedModule>):Void {
		if (resolved == null)
			return;
		for (m in resolved) {
			final mp = ResolvedModule.getModulePath(m);
			if (mp != null && mp.length > 0)
				visited.set(mp, true);
		}
	}

	public function drainNewModules():Array<ResolvedModule> {
		if (pending.length == 0)
			return [];
		final out = pending.copy();
		pending.resize(0);
		return out;
	}

	/**
		Ensure that a type path can be resolved against the shared `TyperIndex`, loading a module
		on-demand if needed.

		Returns the resolved nominal semantic surface or `null` if it still cannot be resolved.
	**/
	override public function ensureTypeAvailable(typePath:String, packagePath:String, imports:Array<String>):Null<TyNominalInfo> {
		if (typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		final trace = Sys.getEnv("HXHX_TRACE_MODULE_LOADER") == "1";

		// Fast path: already indexed.
		final pkg = packagePath == null ? "" : packagePath;
		final hit0 = index == null ? null : index.resolveTypePath(raw, pkg, imports);
		if (hit0 != null)
			return hit0;

		// Try deriving candidate module paths from the typing context.
		final candidates = candidateModulePaths(raw, pkg, imports);
		if (trace)
			Sys.println("loader_resolve type=" + raw + " pkg=" + pkg + " candidates=" + candidates.join(","));
		for (mp in candidates) {
			if (mp == null || mp.length == 0)
				continue;
			loadModuleByPath(mp);

			final hit = index == null ? null : index.resolveTypePath(raw, pkg, imports);
			if (hit != null)
				return hit;
		}

		if (onMissingType != null) {
			for (mp in candidates) {
				if (mp == null || mp.length == 0 || typeNotFoundTried.exists(mp))
					continue;
				typeNotFoundTried.set(mp, true);
				if (!invokeOnMissingType(mp))
					continue;
				loadModuleByPath(mp);
				final hit = index == null ? null : index.resolveTypePath(raw, pkg, imports);
				if (hit != null)
					return hit;
			}
		}

		return null;
	}

	static function candidateModulePaths(typePath:String, packagePath:String, imports:Array<String>):Array<String> {
		final out = new Array<String>();
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		if (raw.length == 0)
			return out;

		// Fully-qualified candidate first.
		if (raw.indexOf(".") >= 0)
			out.push(raw);

		// Imported candidates (match by last segment).
		if (imports != null) {
			for (imp in imports) {
				if (imp == null)
					continue;
				final s = StringTools.trim(imp);
				if (s.length == 0)
					continue;
				if (StringTools.endsWith(s, ".*"))
					continue;
				final parts = s.split(".");
				final last = parts.length == 0 ? "" : parts[parts.length - 1];
				if (last == raw)
					out.push(s);
			}
		}

		// Same-package / parent-package candidates.
		//
		// Why
		// - Upstream resolves unqualified type names by searching the current package and then
		//   walking up parent packages, then root. This means code in `a.b` can refer to `Util`
		//   and have it resolve to `a.Util` or root `Util` without an explicit import, as long
		//   as that module exists.
		//
		// Example
		// - `package runci.targets; ... Linux.requireAptPackages(...)` resolves to `runci.Linux`
		//   even without `import runci.Linux;`.
		final pkg = packagePath == null ? "" : StringTools.trim(packagePath);
		if (pkg.length > 0 && raw.indexOf(".") == -1) {
			var cur = pkg;
			while (true) {
				out.push(cur + "." + raw);
				final lastDot = cur.lastIndexOf(".");
				if (lastDot < 0)
					break;
				cur = cur.substr(0, lastDot);
			}
			out.push(raw);
		}

		// Root-package candidate.
		//
		// Why
		// - In the default package (`packagePath == ""`), unqualified type references like
		//   `Macro.getCases(...)` must still resolve lazily to `Macro.hx`.
		// - Without this candidate, `ensureTypeAvailable("Macro", "", imports)` has no module
		//   path to try, so Stage3 emit can fail later with `Unbound module Macro`.
		if (pkg.length == 0 && raw.indexOf(".") == -1) {
			out.push(raw);
		}

		// Dedupe while preserving order.
		final seen = new haxe.ds.StringMap<Bool>();
		final uniq = new Array<String>();
		for (m in out) {
			if (m == null || m.length == 0)
				continue;
			if (seen.exists(m))
				continue;
			seen.set(m, true);
			uniq.push(m);
		}
		return uniq;
	}

	function loadModuleByPath(modulePath:String):Void {
		if (modulePath == null || modulePath.length == 0)
			return;
		if (visited.exists(modulePath))
			return;
		final trace = Sys.getEnv("HXHX_TRACE_MODULE_LOADER") == "1";

		final filePath = resolveModuleFile(modulePath);
		if (filePath == null) {
			if (trace)
				Sys.println("loader_load miss module=" + modulePath);
			return;
		}

		final source = sourceProvider.readSource(filePath);
		if (source == null) {
			if (trace)
				Sys.println("loader_load read_failed module=" + modulePath + " file=" + filePath);
			return;
		}
		visited.set(modulePath, true);

		inline function isMacroStdModule(modulePath:String, filePath:String):Bool {
			if (modulePath != null && StringTools.startsWith(modulePath, "haxe.macro."))
				return true;
			if (filePath == null || filePath.length == 0)
				return false;
			return filePath.indexOf("/haxe/macro/") != -1 || filePath.indexOf("\\haxe\\macro\\") != -1;
		}

		function cloneDefines(src:haxe.ds.StringMap<String>):haxe.ds.StringMap<String> {
			final out = new haxe.ds.StringMap<String>();
			if (src != null)
				for (k in src.keys())
					out.set(k, src.get(k));
			return out;
		}

		final effectiveDefines = isMacroStdModule(modulePath, filePath) ? (() -> {
			final m = cloneDefines(defines);
			if (!m.exists("macro"))
				m.set("macro", "1");
			if (!m.exists("eval"))
				m.set("eval", "1");
			m;
		})() : defines;
		final filtered = HxConditionalCompilation.filterSource(source, effectiveDefines);
		final parsed = try {
			sourceProvider.parseFilteredSource(filtered, filePath);
		} catch (_:HxParseError) {
			null;
		} catch (_:String) {
			null;
		}
		if (parsed == null) {
			if (trace)
				Sys.println("loader_load parse_failed module=" + modulePath + " file=" + filePath);
			return;
		}

		final rm = new ResolvedModule(modulePath, filePath, parsed);
		pending.push(rm);
		if (trace)
			Sys.println("loader_load ok module=" + modulePath + " file=" + filePath);

		if (index != null)
			index.addResolvedModule(rm);

		// Keep lazily loaded modules link-safe by recursively loading their direct dependencies.
		//
		// Why
		// - ResolverStage computes import closure only for the initial roots.
		// - ModuleLoader can add additional modules during typing, but without dependency expansion
		//   those modules may emit references to missing OCaml units (link-time failures).
		//
		// What
		// - Follow explicit imports (including module-type fallback) and fully-qualified type path
		//   references found in source bodies (e.g. `pkg.Type.member(...)`).
		if (expandDependencies) {
			final decl = parsed.getDecl();
			for (dep in depsForParsedModule(filtered, decl, effectiveDefines)) {
				if (dep == null || dep.length == 0)
					continue;
				if (resolveModuleFile(dep) == null)
					continue;
				loadModuleByPath(dep);
			}
			// Dependency identities may not have existed during the provisional
			// insertion above. Rebuild this module through the same index path so
			// lazy signatures match an eager two-pass build.
			if (index != null)
				index.addResolvedModule(rm);
		}
	}

	static function normalizeImport(raw:String):String {
		if (raw == null)
			return "";
		var s = StringTools.trim(raw);
		if (s.length == 0)
			return "";
		if (StringTools.startsWith(s, "using "))
			s = StringTools.trim(s.substr("using ".length));
		final asIdx = s.indexOf(" as ");
		if (asIdx >= 0)
			s = StringTools.trim(s.substr(0, asIdx));
		return s;
	}

	static function implicitQualifiedTypeDeps(source:String, ?defines:haxe.ds.StringMap<String>):Array<String> {
		if (source == null || source.length == 0)
			return [];

		final candidates = new haxe.ds.StringMap<Bool>();
		for (line in source.split("\n")) {
			final trimmed = StringTools.trim(line);
			if (StringTools.startsWith(trimmed, "@:"))
				continue;

			final re = ~/\b(([A-Za-z_][A-Za-z0-9_]*\.)+[A-Z][A-Za-z0-9_]*)\b/g;
			var pos = 0;
			while (re.matchSub(line, pos, -1)) {
				final dep = re.matched(1);
				if (dep != null && dep.length > 0 && !HxConditionalCompilation.isInactiveTargetQualifiedTypePath(dep, defines))
					candidates.set(dep, true);
				final mp = re.matchedPos();
				pos = mp.pos + mp.len;
			}
		}

		final out = new Array<String>();
		for (dep in candidates.keys())
			out.push(dep);
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	function depsForParsedModule(filteredSource:String, decl:HxModuleDecl, ?defines:haxe.ds.StringMap<String>):Array<String> {
		final out = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();

		inline function push(dep:String):Void {
			if (dep == null || dep.length == 0)
				return;
			if (seen.exists(dep))
				return;
			seen.set(dep, true);
			out.push(dep);
		}

		final modulePkg = HxModuleDecl.getPackagePath(decl);
		for (rawImport in HxModuleDecl.getImports(decl)) {
			final imp = normalizeImport(rawImport);
			if (imp.length == 0)
				continue;

			final resolvedImp = {
				final existsDirect = resolveModuleFile(imp) != null;
				if (existsDirect)
					imp
				else {
					final dot = imp.indexOf(".");
					final head = dot == -1 ? imp : imp.substr(0, dot);
					final head0 = head.length == 0 ? 0 : head.charCodeAt(0);
					final headIsUpper = head0 >= "A".code && head0 <= "Z".code;
					if (headIsUpper && modulePkg != null && modulePkg.length > 0 && !StringTools.startsWith(imp, modulePkg + "."))
						modulePkg + "." + imp
					else
						imp;
				}
			}

			if (StringTools.endsWith(resolvedImp, ".*")) {
				final base = resolvedImp.substr(0, resolvedImp.length - 2);
				if (resolveModuleFile(base) != null)
					push(base);
				continue;
			}

			push(resolvedImp);
		}

		for (dep in implicitQualifiedTypeDeps(filteredSource, defines))
			push(dep);
		return out;
	}

	function resolveModuleFile(modulePath:String):Null<String> {
		return sourceProvider.resolveModuleFile(classPaths, modulePath);
	}
}
