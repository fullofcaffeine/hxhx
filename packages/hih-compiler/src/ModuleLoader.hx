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

	// Module-path based cycle/dup guard.
	final visited:haxe.ds.StringMap<Bool>;

	// Newly loaded modules (drained by the Stage3 driver).
	final pending:Array<ResolvedModule>;

	public function new(classPaths:Array<String>, defines:haxe.ds.StringMap<String>, index:TyperIndex) {
		super();
		this.classPaths = classPaths == null ? [] : classPaths;
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.index = index;
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

		final source = try sys.io.File.getContent(filePath) catch (_:Dynamic) null;
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
		final parsed = try ParserStage.parse(filtered, filePath) catch (_:Dynamic) null;
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
	}

	function resolveModuleFile(modulePath:String):Null<String> {
		final parts = modulePath.split(".");
		if (parts.length == 0) return null;

		final direct = parts.join("/") + ".hx";
		for (cp in classPaths) {
			final candidate = Path.join([cp, direct]);
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) return candidate;
		}

		// Sub-type fallback: pack.Mod.SubType -> pack/Mod.hx
		if (parts.length >= 2) {
			final fallbackParts = parts.slice(0, parts.length - 1);
			final fallback = fallbackParts.join("/") + ".hx";
			for (cp in classPaths) {
				final candidate = Path.join([cp, fallback]);
				if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) return candidate;
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
