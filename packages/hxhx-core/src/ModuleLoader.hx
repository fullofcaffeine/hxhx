import TyTypeDeclaration.TyTypeResolutionContext;

/** Dependency recursion may observe headers; only Ready permits completed signature use. */
private enum SignaturePreparationState {
	Preparing;
	Ready;
	Failed;
}

private typedef MissingTypeHook = {
	function invoke(modulePath:String):Bool;
}

private typedef ModulePreparationHook = {
	function invoke(module:ResolvedModule):ResolvedModule;
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
	  - It tracks requested paths and selected source files separately. Secondary
		types and static members cannot cause the same source to enter typing twice.
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
	final prepareModule:Null<ModulePreparationHook>;
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
	final visitedSourceFiles = new haxe.ds.StringMap<Bool>();
	final typeNotFoundTried:haxe.ds.StringMap<Bool>;

	// Newly loaded modules (drained by the Stage3 driver).
	final pending:Array<ResolvedModule>;
	final signatureStates = new haxe.ds.StringMap<SignaturePreparationState>();

	public function new(classPaths:Array<String>, defines:haxe.ds.StringMap<String>, index:TyperIndex, ?onMissingType:String->Bool,
			?expandDependencies:Bool = true, ?sourceProvider:CompilerSourceProvider, ?prepareModule:ResolvedModule->ResolvedModule) {
		super();
		this.classPaths = classPaths == null ? [] : classPaths;
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.index = index;
		this.onMissingType = onMissingType == null ? null : {invoke: onMissingType};
		this.prepareModule = prepareModule == null ? null : {invoke: prepareModule};
		this.expandDependencies = expandDependencies;
		this.sourceProvider = sourceProvider == null ? new CompilerSourceProvider() : sourceProvider;
		this.visited = new haxe.ds.StringMap<Bool>();
		this.typeNotFoundTried = new haxe.ds.StringMap<Bool>();
		this.pending = [];
	}

	/**
		Run the optional request-owned preparation step before a module becomes visible to typing.

		A preparer may replace parsed declarations, for example after a compiler extension adds
		members, but it must preserve the module's logical identity. The loader itself remains
		unaware of macro or target semantics.
	**/
	function prepareResolvedModule(module:ResolvedModule):ResolvedModule {
		if (prepareModule == null)
			return module;
		final prepared = prepareModule.invoke(module);
		if (prepared == null)
			throw "module preparation returned no module for " + ResolvedModule.getModulePath(module);
		final originalPath = ResolvedModule.getModulePath(module);
		if (ResolvedModule.getModulePath(prepared) != originalPath)
			throw "module preparation changed the module path from " + originalPath + " to " + ResolvedModule.getModulePath(prepared);
		if (ResolvedModule.getFilePath(prepared) != ResolvedModule.getFilePath(module))
			throw "module preparation changed the source file for " + originalPath;
		return prepared;
	}

	inline function invokeOnMissingType(mp:String):Bool {
		return onMissingType == null ? false : onMissingType.invoke(mp);
	}

	/** Register prepared roots, then finish their signatures before body typing starts. */
	public function markResolvedAlready(resolved:Array<ResolvedModule>):Void {
		if (resolved == null)
			return;
		index.registerResolvedModules(resolved);
		for (m in resolved) {
			final mp = ResolvedModule.getModulePath(m);
			if (mp != null && mp.length > 0)
				visited.set(mp, true);
			visitedSourceFiles.set(haxe.io.Path.normalize(ResolvedModule.getFilePath(m)), true);
		}
		for (module in resolved)
			prepareSignatureDependencies(module);
	}

	/**
		Load declaration-only dependencies through ordinary contextual lookup.

		Discover headers breadth first in declaration order. This preserves request
		preparation order while ordinary class cycles see only header identities.
		Publish signatures after every reachable declaration header is available.
	**/
	function prepareSignatureDependencies(module:ResolvedModule):Void {
		if (index == null)
			return;
		final modulePath = ResolvedModule.getModulePath(module);
		if (signatureStates.exists(modulePath)) {
			switch (signatureStates.get(modulePath)) {
				case Preparing | Ready:
					return;
				case Failed:
					throw "signature preparation previously failed for " + modulePath;
			}
		}
		final work = [module];
		final queued = new haxe.ds.StringMap<Bool>();
		queued.set(modulePath, true);
		function failPreparation():Void {
			for (entry in work)
				if (signatureStates.get(entry.modulePath) == Preparing)
					signatureStates.set(entry.modulePath, Failed);
		}
		try {
			var cursor = 0;
			while (cursor < work.length) {
				final current = work[cursor++];
				if (signatureStates.get(current.modulePath) == Ready)
					continue;
				if (signatureStates.get(current.modulePath) == Failed)
					throw "signature preparation previously failed for " + current.modulePath;
				signatureStates.set(current.modulePath, Preparing);
				final declaration = current.parsed.getDecl();
				final context:TyTypeResolutionContext = {
					packagePath: HxModuleDecl.getPackagePath(declaration),
					modulePath: current.modulePath,
					directives: HxModuleDecl.getDirectives(declaration),
					filePath: current.filePath,
					position: HxPos.unknown(),
					parameters: []
				};
				for (path in TySignatureDependencies.declared(declaration, current.filePath)) {
					final dependency = declarationHeadersAvailable(path, context);
					if (dependency == null || queued.exists(dependency.getModulePath()))
						continue;
					final owner = index.getRegisteredModule(dependency.getModulePath());
					if (owner != null) {
						queued.set(owner.modulePath, true);
						work.push(owner);
					}
				}
			}
			for (entry in work) {
				index.publishResolvedModule(entry);
				signatureStates.set(entry.modulePath, Ready);
			}
		} catch (error:TyperError) {
			failPreparation();
			throw error;
		} catch (error:String) {
			failPreparation();
			throw error;
		} catch (error:haxe.Exception) {
			failPreparation();
			throw error;
		}
		// Body-only link dependencies are independent of the now-final signatures.
		if (expandDependencies)
			for (entry in work)
				if (pending.indexOf(entry) >= 0)
					for (dependency in depsForParsedModule(entry.parsed.getSource(), entry.parsed.getDecl(), moduleDefines(entry.modulePath, entry.filePath)))
						if (resolveModuleFile(dependency) != null)
							loadModuleByPath(dependency);
	}

	/** Load aliases and nominal declarations through the same contextual search. */
	override public function ensureDeclarationAvailable(path:String, context:TyTypeResolutionContext):Null<TyTypeDeclaration> {
		final declaration = declarationHeadersAvailable(path, context);
		if (declaration != null) {
			final owner = index.getRegisteredModule(declaration.getModulePath());
			if (owner != null)
				prepareSignatureDependencies(owner);
		}
		return declaration;
	}

	/** Discover source headers without recursively publishing another module's signatures. */
	function declarationHeadersAvailable(path:String, context:TyTypeResolutionContext):Null<TyTypeDeclaration> {
		var hit = index.resolveTypeDeclaration(path, context);
		if (hit != null)
			return hit;
		final candidates = candidateModulePaths(path, context.packagePath, context.directives);
		for (candidate in candidates) {
			loadModuleHeadersByPath(candidate);
			hit = index.resolveTypeDeclaration(path, context);
			if (hit != null)
				return hit;
		}
		if (onMissingType != null)
			for (candidate in candidates) {
				if (typeNotFoundTried.exists(candidate))
					continue;
				typeNotFoundTried.set(candidate, true);
				if (invokeOnMissingType(candidate)) {
					loadModuleHeadersByPath(candidate);
					hit = index.resolveTypeDeclaration(path, context);
					if (hit != null)
						return hit;
				}
			}
		return null;
	}

	override public function hasDefine(name:String):Bool
		return defines.exists(name);

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
	override public function ensureTypeAvailable(typePath:String, packagePath:String, directives:Array<HxModuleDirective>,
			?resolvedDirectives:Array<TyModuleDirective>):Null<TyNominalInfo> {
		if (typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		final context:TyTypeResolutionContext = {
			packagePath: packagePath == null ? "" : packagePath,
			modulePath: "",
			directives: directives == null ? [] : directives,
			filePath: "<type lookup>",
			position: HxPos.unknown(),
			parameters: []
		};
		if (ensureDeclarationAvailable(raw, context) == null)
			return null;
		final identity = index.resolveTypeUse(TyType.unresolved(raw, []), context).getType().getNominalIdentity();
		return identity == null ? null : index.getByFullName(identity.getCanonicalName());
	}

	function candidateModulePaths(typePath:String, packagePath:String, directives:Array<HxModuleDirective>,
			?resolvedDirectives:Array<TyModuleDirective>):Array<String> {
		final out = new Array<String>();
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		if (raw.length == 0)
			return out;

		// Fully-qualified candidate first.
		if (raw.indexOf(".") >= 0)
			out.push(raw);

		// Imported candidates (match by last segment).
		if (resolvedDirectives != null) {
			for (offset in 0...resolvedDirectives.length) {
				final directive = resolvedDirectives[resolvedDirectives.length - 1 - offset];
				final source = directive.getSource();
				switch (directive.getKind()) {
					case TypeImport:
						if (HxModuleDirective.getImportedLocalName(source) == raw)
							out.push(HxModuleDirective.getPath(source));
						if (HxModuleDirective.getKind(source).match(ImportNormal) && index != null)
							for (provider in directive.getProviders()) {
								final providerInfo = index.getByFullName(provider.getCanonicalName());
								if (providerInfo != null && providerInfo.getShortName() == raw)
									out.push(providerInfo.getModulePath());
							}
					case PackageWildcardImport:
						out.push(HxModuleDirective.getPath(source) + "." + raw);
					case StaticMemberImport(_) | StaticWildcardImport | UsingType | Unresolved:
				}
			}
		} else if (directives != null) {
			for (offset in 0...directives.length) {
				final directive = directives[directives.length - 1 - offset];
				switch (HxModuleDirective.getKind(directive)) {
					case ImportNormal:
						if (HxModuleDirective.getImportedLocalName(directive) == raw)
							out.push(HxModuleDirective.getPath(directive));
						final importPath = HxModuleDirective.getPath(directive);
						// Loading this module can reveal a secondary declaration even
						// when no same-named main type exists yet.
						out.push(importPath);
					case ImportAlias(_):
						if (HxModuleDirective.getImportedLocalName(directive) == raw)
							out.push(HxModuleDirective.getPath(directive));
					case ImportAll:
						final importPath = HxModuleDirective.getPath(directive);
						// An exact type wildcard exposes static members only. When
						// the provider is already known, do not turn a secondary type
						// in the same module into a package-style import.
						if (index == null || index.getByFullName(importPath) == null)
							out.push(importPath + "." + raw);
					case Using:
				}
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

	/** Macro standard modules retain their existing conditional compilation policy. */
	function moduleDefines(modulePath:String, filePath:String):haxe.ds.StringMap<String> {
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

		return isMacroStdModule(modulePath, filePath) ? (() -> {
			final m = cloneDefines(defines);
			if (!m.exists("macro"))
				m.set("macro", "1");
			if (!m.exists("eval"))
				m.set("eval", "1");
			m;
		})() : defines;
	}

	/** Complete one source module after its declaration headers have been discovered. */
	function loadModuleByPath(modulePath:String):Void {
		final module = loadModuleHeadersByPath(modulePath);
		if (module != null)
			prepareSignatureDependencies(module);
	}

	function loadModuleHeadersByPath(modulePath:String):Null<ResolvedModule> {
		if (modulePath == null || modulePath.length == 0)
			return null;
		if (visited.exists(modulePath))
			return index.getRegisteredModule(modulePath);
		final trace = Sys.getEnv("HXHX_TRACE_MODULE_LOADER") == "1";

		final resolution = sourceProvider.resolveModule(classPaths, modulePath);
		final filePath = resolution.filePath;
		if (filePath == null) {
			if (trace)
				Sys.println("loader_load miss module=" + modulePath);
			return null;
		}
		// Resolve every new lookup before checking the source. Its observation must
		// still record whether a direct file shadows a secondary-type fallback.
		final selectedFileKey = haxe.io.Path.normalize(filePath);
		if (visitedSourceFiles.exists(selectedFileKey)) {
			visited.set(modulePath, true);
			return null;
		}

		final source = sourceProvider.readSource(filePath);
		if (source == null) {
			if (trace)
				Sys.println("loader_load read_failed module=" + modulePath + " file=" + filePath);
			return null;
		}
		visited.set(modulePath, true);

		final effectiveDefines = moduleDefines(modulePath, filePath);
		final conditional = HxConditionalCompilation.filterSourceObserved(source, effectiveDefines);
		final filtered = conditional.getFilteredSource();
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
			return null;
		}

		// Match eager resolution: declarations belong to the source module, while
		// the origin retains the exact lookup that selected that source.
		final packagePath = HxModuleDecl.getPackagePath(parsed.getDecl());
		final moduleName = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(filePath));
		final canonicalModulePath = packagePath == null || packagePath.length == 0 ? moduleName : packagePath + "." + moduleName;
		visited.set(canonicalModulePath, true);
		visitedSourceFiles.set(selectedFileKey, true);
		final parsedModule = new ResolvedModule(canonicalModulePath, filePath, parsed, resolution.toOrigin(modulePath), conditional.getObservation());
		final rm = prepareResolvedModule(parsedModule);
		pending.push(rm);
		if (trace)
			Sys.println("loader_load ok module=" + modulePath + " file=" + filePath);

		if (index != null)
			index.registerResolvedModules([rm]);
		return rm;
	}

	static function implicitQualifiedTypeDeps(source:String, ?defines:haxe.ds.StringMap<String>):Array<String> {
		return HxImplicitDependencies.qualifiedTypePaths(source, defines);
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
		for (directive in HxModuleDecl.getDirectives(decl)) {
			final imp = HxModuleDirective.getPath(directive);
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

			if (HxModuleDirective.getKind(directive).match(ImportAll)) {
				if (resolveModuleFile(resolvedImp) != null)
					push(resolvedImp);
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
