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
	final inferredReturnTypes:haxe.ds.StringMap<TyType>;

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
		this.inferredReturnTypes = new haxe.ds.StringMap<TyType>();
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

	/**
		Record a concrete body result for an indexed declaration whose written
		signature did not provide one.

		The declaration index exists before bodies are typed. Calls between methods
		in the same class can use this refinement without mutating the shared index
		or replacing the declaration identity selected by overload resolution.
	**/
	public function recordInferredReturnType(declaration:TyDeclarationInfo, type:TyType):Bool {
		if (declaration == null || type == null || type.isUnknown() || type.isDynamic())
			return false;
		final key = declaration.getIdentity().getCanonicalKey();
		final existing = inferredReturnTypes.get(key);
		if (existing == null) {
			inferredReturnTypes.set(key, type);
			return true;
		}
		final unified = TyType.unify(existing, type);
		if (unified == null || unified.getSemanticKey() == existing.getSemanticKey())
			return false;
		inferredReturnTypes.set(key, unified);
		return true;
	}

	/** Return the body-inferred result for one exact method, or its indexed result. **/
	public function refinedMethodReturnType(declaration:TyDeclarationInfo, indexedType:TyType):TyType {
		if (declaration == null)
			return indexedType;
		final inferred = inferredReturnTypes.get(declaration.getIdentity().getCanonicalKey());
		return inferred == null ? indexedType : inferred;
	}

	/**
		Resolve one unique enum constructor declared by a type in the current module.

		Haxe makes same-module enum constructors available as bare calls. The
		semantic owner is selected here, before target projection. If two enums
		declare the same constructor name, this bounded lookup returns no result
		instead of letting traversal order pick one.
	**/
	public function moduleEnumConstructorMethod(name:String):Null<TyImportedStaticMethod> {
		if (index == null || name == null || name.length == 0)
			return null;
		var selectedProvider:Null<TyNominalInfo> = null;
		var selectedCandidates:Array<TyFunSig> = [];
		for (provider in index.getDeclaredByModulePath(modulePath)) {
			if (!provider.getIsEnum())
				continue;
			final eligible = [
				for (candidate in provider.staticMethodCandidates(name))
					if (provider.declarationForSignature(candidate) != null
						&& provider.declarationForSignature(candidate).getIsEnumConstructor()) candidate
			];
			if (eligible.length == 0)
				continue;
			if (selectedProvider != null)
				return null;
			selectedProvider = provider;
			selectedCandidates = eligible;
		}
		return selectedProvider == null ? null : new TyImportedStaticMethod(selectedProvider, name, selectedCandidates);
	}

	function resolvedProvider(directive:TyModuleDirective):Null<TyNominalInfo> {
		if (directive == null || index == null)
			return null;
		final provider = directive.getSingleProvider();
		return provider == null ? null : index.getByFullName(provider.getCanonicalName());
	}

	static function asClass(info:Null<TyNominalInfo>):Null<TyClassInfo>
		return info != null && Std.isOfType(info, TyClassInfo) ? cast info : null;

	function superclass(info:Null<TyNominalInfo>):Null<TyClassInfo> {
		final cls = asClass(info);
		if (cls == null || index == null)
			return null;
		final superType = cls.getSuperType();
		final identity = superType == null ? null : superType.getNominalIdentity();
		return identity == null ? null : asClass(index.getByFullName(identity.getCanonicalName()));
	}

	function classIsOrExtends(candidate:Null<TyNominalInfo>, ancestor:TyNominalInfo):Bool {
		if (candidate == null || ancestor == null)
			return false;
		final seen = new haxe.ds.StringMap<Bool>();
		var current = asClass(candidate);
		while (current != null) {
			final name = current.getFullName();
			if (name == ancestor.getFullName())
				return true;
			if (seen.exists(name))
				return false;
			seen.set(name, true);
			current = superclass(current);
		}
		return false;
	}

	/**
		Return extension-method groups in Haxe lookup order.

		Later `using` directives and later types from a used module have priority.
		Each result keeps the named using provider separate from the class that
		actually declares an inherited static method. Argument compatibility is
		checked later by the ordinary overload selector.
	**/
	public function extensionMethods(name:String):Array<TyExtensionMethod> {
		final out = new Array<TyExtensionMethod>();
		if (index == null || name == null || name.length == 0)
			return out;
		final current = currentClass();
		for (directiveOffset in 0...resolvedDirectives.length) {
			final directive = resolvedDirectives[resolvedDirectives.length - 1 - directiveOffset];
			if (!directive.getKind().match(UsingType))
				continue;
			final providers = directive.getProviders();
			for (providerOffset in 0...providers.length) {
				final usingIdentity = providers[providers.length - 1 - providerOffset];
				var declaring = index.getByFullName(usingIdentity.getCanonicalName());
				final seen = new haxe.ds.StringMap<Bool>();
				while (declaring != null && !seen.exists(declaring.getFullName())) {
					seen.set(declaring.getFullName(), true);
					final eligible = new Array<TyFunSig>();
					for (candidate in declaring.staticMethodCandidates(name)) {
						final declaration = declaring.declarationForSignature(candidate);
						if (declaration == null || candidate.getArgs().length == 0)
							continue;
						if (declaration.getIsPublic() || classIsOrExtends(current, declaring))
							eligible.push(candidate);
					}
					if (eligible.length > 0)
						out.push(new TyExtensionMethod(usingIdentity, declaring, name, eligible));
					declaring = superclass(declaring);
				}
			}
		}
		return out;
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
