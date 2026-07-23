/**
	Per-module typing context for Stage 3 bootstrap typing.

	Why
	- `TyperIndex` is global, but expression typing also needs local context:
	  - current package/imports (to resolve short type names)
	  - current class (to type `this.x`)
	  - the current file path (for diagnostics)

	What
	- A small record-like object that threads through `TyperStage` during typing.

	How
	- This is intentionally simple and deterministic. When the real Haxe-in-Haxe
	  typer lands, this will evolve toward upstream’s module typing environment.
**/
class TyperContext {
	final index:TyperIndex;
	final loader:Null<LazyTypeLoader>;
	final filePath:String;
	final modulePath:String;
	final packagePath:String;
	final directives:Array<HxModuleDirective>;
	final resolvedDirectives:Array<TyModuleDirective>;
	final classFullName:String;

	public function new(index:TyperIndex, filePath:String, modulePath:String, packagePath:String, directives:Array<HxModuleDirective>, classFullName:String,
			?loader:LazyTypeLoader, ?resolvedDirectives:Array<TyModuleDirective>) {
		this.index = index;
		this.loader = loader;
		this.filePath = filePath == null || filePath.length == 0 ? "<unknown>" : filePath;
		this.modulePath = modulePath == null ? "" : modulePath;
		this.packagePath = packagePath == null ? "" : packagePath;
		this.directives = directives == null ? [] : directives.copy();
		this.resolvedDirectives = resolvedDirectives == null ? [] : resolvedDirectives.copy();
		this.classFullName = classFullName == null ? "" : classFullName;
	}

	/**
		Non-inline getters for cross-module use.

		Why
		- The OCaml build uses dune’s `-opaque`, which can make direct record-label
		  access across compilation units fragile during bootstrap.
		- Exposing accessors keeps downstream stages deterministic.
	**/
	public function getIndex():TyperIndex
		return index;

	public function getFilePath():String
		return filePath;

	public function getModulePath():String
		return modulePath;

	public function getPackagePath():String
		return packagePath;

	public function getDirectives():Array<HxModuleDirective>
		return directives.copy();

	public function getResolvedDirectives():Array<TyModuleDirective>
		return resolvedDirectives.copy();

	public function getClassFullName():String
		return classFullName;

	public function resolveType(typePath:String):Null<TyNominalInfo> {
		if (index == null)
			return null;
		final hit = index.resolveTypePath(typePath, packagePath, directives, resolvedDirectives, modulePath);
		if (hit != null)
			return hit;
		return loader == null ? null : loader.ensureTypeAvailable(typePath, packagePath, directives, resolvedDirectives);
	}

	public function currentClass():Null<TyNominalInfo> {
		return classFullName.length == 0 ? null : resolveType(classFullName);
	}

	function resolvedProvider(directive:TyModuleDirective):Null<TyNominalInfo> {
		if (directive == null || index == null)
			return null;
		final provider = directive.getSingleProvider();
		return provider == null ? null : index.getByFullName(provider.getCanonicalName());
	}

	/** Resolve a bare name introduced by an exact or wildcard static import. **/
	public function importedStaticField(name:String):Null<TyFieldInfo> {
		for (offset in 0...resolvedDirectives.length) {
			final directive = resolvedDirectives[resolvedDirectives.length - 1 - offset];
			final provider = resolvedProvider(directive);
			if (provider == null)
				continue;
			final admitsName = switch (directive.getKind()) {
				case StaticMemberImport(memberName): directive.getStaticLocalName() == name && memberName.length > 0;
				case StaticWildcardImport: true;
				case TypeImport | PackageWildcardImport | UsingType | Unresolved: false;
			};
			if (!admitsName)
				continue;
			final field = switch (directive.getKind()) {
				case StaticMemberImport(memberName): provider.fieldInfo(memberName);
				case _: provider.fieldInfo(name);
			};
			final excludedByWildcard = directive.getKind().match(StaticWildcardImport) && field != null && field.getNoImportGlobal();
			if (field != null && field.getIsStatic() && field.getIsPublic() && !excludedByWildcard)
				return field;
		}
		return null;
	}

	/** Resolve one bare imported method without separating its owner from its original name. **/
	public function importedStaticMethod(name:String):Null<TyImportedStaticMethod> {
		for (offset in 0...resolvedDirectives.length) {
			final directive = resolvedDirectives[resolvedDirectives.length - 1 - offset];
			final provider = resolvedProvider(directive);
			if (provider == null)
				continue;
			final memberName = switch (directive.getKind()) {
				case StaticMemberImport(exactName) if (directive.getStaticLocalName() == name): exactName;
				case StaticWildcardImport: name;
				case _: "";
			};
			if (memberName.length == 0)
				continue;
			final candidates = provider.staticMethodCandidates(memberName);
			final publicCandidates = [
				for (candidate in candidates)
					if (provider.declarationForSignature(candidate) != null
						&& provider.declarationForSignature(candidate).getIsPublic()) candidate
			];
			final eligible = directive.getKind().match(StaticWildcardImport) ? [
				for (candidate in publicCandidates)
					if (!provider.declarationForSignature(candidate).getNoImportGlobal()) candidate
			] : publicCandidates;
			if (eligible.length > 0)
				return new TyImportedStaticMethod(provider, memberName, eligible);
		}
		return null;
	}
}
