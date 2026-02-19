import haxe.io.Path;

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
	- Stage3 still does not model full “module has multiple types” semantics. We index only the
	  main class of each module (consistent with the bootstrap parser/model).
**/
class ModuleLoader extends LazyTypeLoader {
	final classPaths:Array<String>;
	final defines:haxe.ds.StringMap<String>;
	final index:TyperIndex;

	// Directory listing cache used for exact-case path checks on case-insensitive filesystems.
	final dirEntryCache:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;

	// Module-path based cycle/dup guard.
	final visited:haxe.ds.StringMap<Bool>;

	// Newly loaded modules (drained by the Stage3 driver).
	final pending:Array<ResolvedModule>;

	public function new(classPaths:Array<String>, defines:haxe.ds.StringMap<String>, index:TyperIndex) {
		super();
		this.classPaths = classPaths == null ? [] : classPaths;
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.index = index;
		this.dirEntryCache = new haxe.ds.StringMap<haxe.ds.StringMap<Bool>>();
		this.visited = new haxe.ds.StringMap<Bool>();
		this.pending = [];
	}

	public function markResolvedAlready(resolved:Array<ResolvedModule>):Void {
		if (resolved == null) return;
		for (m in resolved) {
			final mp = ResolvedModule.getModulePath(m);
			if (mp != null && mp.length > 0) visited.set(mp, true);
		}
	}

	public function drainNewModules():Array<ResolvedModule> {
		if (pending.length == 0) return [];
		final out = pending.copy();
		pending.resize(0);
		return out;
	}

	/**
		Ensure that a type path can be resolved against the shared `TyperIndex`, loading a module
		on-demand if needed.

		Returns the resolved `TyClassInfo` or `null` if it still cannot be resolved.
	**/
	override public function ensureTypeAvailable(typePath:String, packagePath:String, imports:Array<String>):Null<TyClassInfo> {
		if (typePath == null) return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0) return null;
		final trace = Sys.getEnv("HXHX_TRACE_MODULE_LOADER") == "1";

		// Fast path: already indexed.
		final pkg = packagePath == null ? "" : packagePath;
		final hit0 = index == null ? null : index.resolveTypePath(raw, pkg, imports);
		if (hit0 != null) return hit0;

		// Try deriving candidate module paths from the typing context.
		final candidates = candidateModulePaths(raw, pkg, imports);
		if (trace) Sys.println("loader_resolve type=" + raw + " pkg=" + pkg + " candidates=" + candidates.join(","));
		for (mp in candidates) {
			if (mp == null || mp.length == 0) continue;
			loadModuleByPath(mp);

			final hit = index == null ? null : index.resolveTypePath(raw, pkg, imports);
			if (hit != null) return hit;
		}

		return null;
	}

	static function candidateModulePaths(typePath:String, packagePath:String, imports:Array<String>):Array<String> {
		final out = new Array<String>();
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		if (raw.length == 0) return out;

		// Fully-qualified candidate first.
		if (raw.indexOf(".") >= 0) out.push(raw);

		// Imported candidates (match by last segment).
		if (imports != null) {
			for (imp in imports) {
				if (imp == null) continue;
				final s = StringTools.trim(imp);
				if (s.length == 0) continue;
				if (StringTools.endsWith(s, ".*")) continue;
				final parts = s.split(".");
				final last = parts.length == 0 ? "" : parts[parts.length - 1];
				if (last == raw) out.push(s);
			}
		}

		// Same-package / parent-package candidates.
		//
		// Why
		// - Upstream resolves unqualified type names by searching the current package and then
		//   walking up parent packages. This means code in `a.b` can refer to `Util` and have
		//   it resolve to `a.Util` without an explicit import, as long as `a.Util` exists.
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
				if (lastDot < 0) break;
				cur = cur.substr(0, lastDot);
			}
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
			if (m == null || m.length == 0) continue;
			if (seen.exists(m)) continue;
			seen.set(m, true);
			uniq.push(m);
		}
		return uniq;
	}

	function loadModuleByPath(modulePath:String):Void {
		if (modulePath == null || modulePath.length == 0) return;
		if (visited.exists(modulePath)) return;
		visited.set(modulePath, true);
		final trace = Sys.getEnv("HXHX_TRACE_MODULE_LOADER") == "1";

		final filePath = resolveModuleFile(modulePath);
		if (filePath == null) {
			if (trace) Sys.println("loader_load miss module=" + modulePath);
			return;
		}

		final source = try {
			sys.io.File.getContent(filePath);
		} catch (_:haxe.io.Error) {
			null;
		} catch (_:String) {
			null;
		}
		if (source == null) {
			if (trace) Sys.println("loader_load read_failed module=" + modulePath + " file=" + filePath);
			return;
		}

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

		final effectiveDefines = isMacroStdModule(modulePath, filePath)
			? (() -> {
				final m = cloneDefines(defines);
				if (!m.exists("macro")) m.set("macro", "1");
				if (!m.exists("eval")) m.set("eval", "1");
				m;
			})()
			: defines;
		final filtered = HxConditionalCompilation.filterSource(source, effectiveDefines);
		final parsed = try {
			ParserStage.parse(filtered, filePath);
		} catch (_:HxParseError) {
			null;
		} catch (_:String) {
			null;
		}
		if (parsed == null) {
			if (trace) Sys.println("loader_load parse_failed module=" + modulePath + " file=" + filePath);
			return;
		}

		final rm = new ResolvedModule(modulePath, filePath, parsed);
		pending.push(rm);
		if (trace) Sys.println("loader_load ok module=" + modulePath + " file=" + filePath);

		if (index != null) {
			for (info in TyperIndexBuild.fromResolvedModule(rm)) {
				if (info != null) index.addClass(info);
			}
		}

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
		final decl = parsed.getDecl();
		for (dep in depsForParsedModule(filtered, decl)) {
			if (dep == null || dep.length == 0) continue;
			if (resolveModuleFile(dep) == null) continue;
			loadModuleByPath(dep);
		}
	}

	static function normalizeImport(raw:String):Null<String> {
		if (raw == null) return null;
		var s = StringTools.trim(raw);
		if (s.length == 0) return null;
		if (StringTools.startsWith(s, "using ")) s = StringTools.trim(s.substr("using ".length));
		final asIdx = s.indexOf(" as ");
		if (asIdx >= 0) s = StringTools.trim(s.substr(0, asIdx));
		return s.length == 0 ? null : s;
	}

	static function implicitQualifiedTypeDeps(source:String):Array<String> {
		if (source == null || source.length == 0) return [];

		final candidates = new haxe.ds.StringMap<Bool>();
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

	function depsForParsedModule(filteredSource:String, decl:HxModuleDecl):Array<String> {
		final out = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();

		inline function push(dep:String):Void {
			if (dep == null || dep.length == 0) return;
			if (seen.exists(dep)) return;
			seen.set(dep, true);
			out.push(dep);
		}

		final modulePkg = HxModuleDecl.getPackagePath(decl);
		for (rawImport in HxModuleDecl.getImports(decl)) {
			final imp = normalizeImport(rawImport);
			if (imp == null) continue;

			final resolvedImp = {
				final existsDirect = resolveModuleFile(imp) != null;
				if (existsDirect) imp else {
					final dot = imp.indexOf(".");
					final head = dot == -1 ? imp : imp.substr(0, dot);
					final head0 = head.length == 0 ? 0 : head.charCodeAt(0);
					final headIsUpper = head0 >= "A".code && head0 <= "Z".code;
					if (headIsUpper && modulePkg != null && modulePkg.length > 0 && !StringTools.startsWith(imp, modulePkg + ".")) modulePkg + "." + imp else imp;
				}
			}

			if (StringTools.endsWith(resolvedImp, ".*")) {
				final base = resolvedImp.substr(0, resolvedImp.length - 2);
				if (resolveModuleFile(base) != null) push(base);
				continue;
			}

			push(resolvedImp);
		}

		for (dep in implicitQualifiedTypeDeps(filteredSource)) push(dep);
		return out;
	}

	function resolveModuleFile(modulePath:String):Null<String> {
		inline function fileExistsExactCase(path:String):Bool {
			if (path == null || path.length == 0) return false;
			if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return false;
			final dir = Path.directory(path);
			if (dir == null || dir.length == 0) return true;
			final base = Path.withoutDirectory(path);
			var entries = dirEntryCache.get(dir);
			if (entries == null) {
				entries = new haxe.ds.StringMap<Bool>();
				try {
					for (name in sys.FileSystem.readDirectory(dir)) {
						if (name != null && name.length > 0) entries.set(name, true);
					}
				} catch (_:haxe.io.Error) {} catch (_:String) {}
				dirEntryCache.set(dir, entries);
			}
			return entries.exists(base);
		}

		final parts = modulePath.split(".");
		if (parts.length == 0) return null;

		final direct = parts.join("/") + ".hx";
		for (cp in classPaths) {
			final candidate = Path.join([cp, direct]);
			if (fileExistsExactCase(candidate)) return candidate;
		}

		// Sub-type fallback: pack.Mod.SubType -> pack/Mod.hx
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

/**
	Small helper to build `TyClassInfo` incrementally (without rebuilding a whole `TyperIndex`).

	Why
	- `TyperIndex.build(...)` scans a whole resolved module list.
	- The lazy loader needs to add a single module’s signature into the existing index.
**/
class TyperIndexBuild {
	static function classFullName(pkg:String, cls:String):String {
		final p = pkg == null ? "" : StringTools.trim(pkg);
		return (p.length == 0) ? cls : (p + "." + cls);
	}

	static function expectedModuleNameFromFile(filePath:Null<String>):Null<String> {
		if (filePath == null || filePath.length == 0) return null;
		final name = Path.withoutDirectory(filePath);
		final dot = name.lastIndexOf(".");
		return dot <= 0 ? name : name.substr(0, dot);
	}

	static function classFullNameInModule(pkg:String, moduleName:Null<String>, clsName:String):String {
		final p = pkg == null ? "" : StringTools.trim(pkg);
		final m0 = moduleName == null ? "" : StringTools.trim(moduleName);
		final m = (m0.length == 0 || m0 == "Unknown") ? "" : m0;
		final c = clsName == null ? "" : StringTools.trim(clsName);

		var prefix = p;
		if (m.length > 0 && c.length > 0 && c != m) {
			prefix = prefix.length == 0 ? m : (prefix + "." + m);
		}
		return prefix.length == 0 ? c : (prefix + "." + c);
	}

	public static function fromResolvedModule(m:ResolvedModule):Array<TyClassInfo> {
		final out = new Array<TyClassInfo>();
		if (m == null) return out;
		final pm = ResolvedModule.getParsed(m);
		if (pm == null) return out;
		final decl = pm.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final moduleName = expectedModuleNameFromFile(ResolvedModule.getFilePath(m));

		for (cls in HxModuleDecl.getClasses(decl)) {
			final clsName = HxClassDecl.getName(cls);
			if (clsName == null || clsName.length == 0 || clsName == "Unknown") continue;
			final full = classFullNameInModule(pkg, moduleName, clsName);

			final fields = new haxe.ds.StringMap<TyType>();
			for (f in HxClassDecl.getFields(cls)) {
				fields.set(HxFieldDecl.getName(f), TyType.fromHintText(HxFieldDecl.getTypeHint(f)));
			}

			final statics = new haxe.ds.StringMap<TyFunSig>();
			final instances = new haxe.ds.StringMap<TyFunSig>();
			for (fn in HxClassDecl.getFunctions(cls)) {
				final fnName = HxFunctionDecl.getName(fn);
				final isStatic = HxFunctionDecl.getIsStatic(fn);
				final args = new Array<TyType>();
				for (a in HxFunctionDecl.getArgs(fn)) args.push(TyType.fromHintText(HxFunctionArg.getTypeHint(a)));

				final retHint = HxFunctionDecl.getReturnTypeHint(fn);
				final ret = (fnName == "new") ? TyType.fromHintText(full) : TyType.fromHintText(retHint);
				final sig = new TyFunSig(fnName, isStatic, args, ret);
				if (isStatic) statics.set(fnName, sig) else instances.set(fnName, sig);
			}

			out.push(new TyClassInfo(full, clsName, ResolvedModule.getModulePath(m), fields, statics, instances));
		}

		return out;
	}
}
