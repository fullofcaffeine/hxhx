/**
	Program-level type index for Stage 3 bootstrap typing.

	Why
	- `TyperStage.typeModule` runs per-module, but real typing needs knowledge
	  of other modules on the classpath (imports, `new`, static calls).
	- This index is the smallest “shared context” that lets us type common
	  upstream patterns without implementing the full Haxe module cache.

	What
	- Maps:
	  - `fullName` (e.g. `demo.Util`) → `TyClassInfo`
	  - `shortName` (e.g. `Util`) → one or more `TyClassInfo` candidates

	How
	- Built from `ResolvedModule` by scanning parsed declarations:
	  - class name + package
	  - `var` fields (name + type hint)
	  - function signatures (arg hints + return hint)
**/
import haxe.io.Path;

class TyperIndex {
	final byFullName:haxe.ds.StringMap<TyClassInfo>;
	final byShortName:haxe.ds.StringMap<Array<TyClassInfo>>;

	public function new() {
		byFullName = new haxe.ds.StringMap();
		byShortName = new haxe.ds.StringMap();
	}

	public function getByFullName(fullName:String):Null<TyClassInfo> {
		return byFullName.exists(fullName) ? byFullName.get(fullName) : null;
	}

	public function getByShortName(shortName:String):Array<TyClassInfo> {
		return byShortName.exists(shortName) ? byShortName.get(shortName) : [];
	}

	public function addClass(info:TyClassInfo):Void {
		if (info == null) return;
		final fullName = info.getFullName();
		byFullName.set(fullName, info);
		final shortName = info.getShortName();
		final arr = byShortName.exists(shortName) ? byShortName.get(shortName) : [];
		arr.push(info);
		byShortName.set(shortName, arr);
	}

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
		// Haxe module-local helper types are addressed as `package.Module.Helper`.
		if (m.length > 0 && c.length > 0 && c != m) {
			prefix = prefix.length == 0 ? m : (prefix + "." + m);
		}
		return prefix.length == 0 ? c : (prefix + "." + c);
	}

	public static function build(resolved:Array<ResolvedModule>):TyperIndex {
		final idx = new TyperIndex();
		if (resolved == null) return idx;

		for (m in resolved) {
			final pm = ResolvedModule.getParsed(m);
			final decl = pm.getDecl();
			final pkg = HxModuleDecl.getPackagePath(decl);
			final moduleName = expectedModuleNameFromFile(ResolvedModule.getFilePath(m));

			// Index every type declared in the module so module-local helper types resolve.
			//
			// Haxe rule (relevant subset):
			// - Main type: `package.ModuleName` (where `ModuleName == <file base name>`)
			// - Helper type: `package.ModuleName.Helper`
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

				idx.addClass(new TyClassInfo(full, clsName, ResolvedModule.getModulePath(m), fields, statics, instances));
			}
		}

		return idx;
	}

	public function resolveTypePath(typePath:String, packagePath:String, imports:Array<String>):Null<TyClassInfo> {
		if (typePath == null) return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0) return null;

		// If it looks fully qualified, try it directly first.
		if (raw.indexOf(".") >= 0) {
			final direct = getByFullName(raw);
			if (direct != null) return direct;
		}

		// Try explicit imports (match by last segment).
		if (imports != null) {
			for (imp in imports) {
				if (imp == null || imp.length == 0) continue;
				final parts = imp.split(".");
				final last = parts.length == 0 ? "" : parts[parts.length - 1];
				if (last == raw) {
					final hit = getByFullName(imp);
					if (hit != null) return hit;
				}
			}
		}

		// Try same package / parent packages.
		//
		// Why
		// - Upstream Haxe resolves unqualified type names by searching the current package
		//   and then walking up parent packages (e.g. `runci.targets.Php` can reference
		//   `Linux` from `runci.Linux` without an explicit import).
		//
		// How
		// - Check `packagePath.raw` first (`pkg + "." + raw`), then progressively drop
		//   the last segment and retry until the package is empty.
		final pkg = packagePath == null ? "" : StringTools.trim(packagePath);
		if (pkg.length > 0) {
			var cur = pkg;
			while (true) {
				final candidate = cur + "." + raw;
				final hit = getByFullName(candidate);
				if (hit != null) return hit;
				final lastDot = cur.lastIndexOf(".");
				if (lastDot < 0) break;
				cur = cur.substr(0, lastDot);
			}
		}

		// Fallback: if unique short-name exists in the index, accept it.
		final alts = getByShortName(raw);
		return alts.length == 1 ? alts[0] : null;
	}
}
