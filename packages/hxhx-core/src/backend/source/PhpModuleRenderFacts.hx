package backend.source;

typedef PhpModuleLocalTypeNameFact = {
	final source:String;
	final emitted:String;
};

typedef PhpModuleImportedTypeAliasFact = {
	final local:String;
	final qualified:String;
};

typedef PhpModuleRenderContribution = {
	final projection:TypedBackendModuleProjection;
	final resolvedDirectives:Array<TyModuleDirective>;
};

/**
	Immutable PHP naming facts visible inside one exact Haxe source module.

	Every request-owned PHP function renderer receives the record for its source
	module. Local type spellings come from strict projected classes and the
	program-wide emitted-name record. Imported aliases come from resolved typed
	directives, never parsed import text. Exact program, module, and PHP schema
	revisions make a mismatch fail before rendering.
**/
class PhpModuleRenderFacts {
	final programRevision:String;
	final moduleRevision:String;
	final moduleIdentity:String;
	final localTypeNames:Array<PhpModuleLocalTypeNameFact>;
	final importedTypeAliases:Array<PhpModuleImportedTypeAliasFact>;
	final usingTypeIdentities:Array<String>;
	final localTypeNameIndex:haxe.ds.StringMap<String>;
	final importedTypeAliasIndex:haxe.ds.StringMap<String>;
	final canonicalIdentity:String;

	public function new(programFacts:PhpProgramRenderFacts, moduleRevision:String, moduleIdentity:String, contributions:Array<PhpModuleRenderContribution>) {
		if (programFacts == null)
			throw "PHP module render facts require exact program facts";
		programRevision = normalize(programFacts.getProgramRevision());
		this.moduleRevision = normalize(moduleRevision);
		this.moduleIdentity = normalize(moduleIdentity);
		if (programRevision.length == 0)
			throw "PHP module render facts require an exact typed-program revision";
		if (this.moduleRevision.length == 0)
			throw "PHP module render facts require an exact typed-module revision";
		if (this.moduleIdentity.length == 0)
			throw "PHP module render facts require an exact source-module identity";
		if (contributions == null || contributions.length == 0)
			throw "PHP module render facts require at least one typed module contribution";

		localTypeNameIndex = new haxe.ds.StringMap<String>();
		importedTypeAliasIndex = new haxe.ds.StringMap<String>();
		final usingTypeIdentityIndex = new haxe.ds.StringMap<Bool>();
		final orderedUsingTypeIdentities = new Array<String>();
		final moduleName = this.moduleIdentity.indexOf(".") < 0 ? this.moduleIdentity : this.moduleIdentity.substr(this.moduleIdentity.lastIndexOf(".") + 1);
		for (contribution in contributions) {
			if (contribution == null || contribution.projection == null)
				throw "PHP module render facts contain a null module contribution";
			for (projectedClass in contribution.projection.getClasses()) {
				if (projectedClass == null)
					throw "PHP module render facts contain a null class projection";
				final rawName = normalize(HxClassDecl.getName(projectedClass.getDeclaration()));
				final shortName = PhpName.typeIdentifier(rawName);
				final exactTypeName = rawName == moduleName ? this.moduleIdentity : this.moduleIdentity + "." + rawName;
				final emittedName = programFacts.findEmittedTypeName(exactTypeName);
				if (emittedName == null || emittedName.length == 0)
					throw "PHP module render facts cannot find emitted type " + exactTypeName;
				addExact(localTypeNameIndex, shortName, emittedName, "local type", this.moduleIdentity);
			}
			if (contribution.resolvedDirectives != null)
				for (directive in contribution.resolvedDirectives) {
					addResolvedImport(directive);
					if (directive != null && directive.getKind().match(UsingType))
						for (provider in directive.getProviders()) {
							final identity = provider.getCanonicalName();
							if (!usingTypeIdentityIndex.exists(identity)) {
								usingTypeIdentityIndex.set(identity, true);
								orderedUsingTypeIdentities.push(identity);
							}
						}
				}
		}

		final localNames = [for (name in localTypeNameIndex.keys()) name];
		localNames.sort((left, right) -> Reflect.compare(left, right));
		localTypeNames = [
			for (name in localNames)
				{
					source: name,
					emitted: localTypeNameIndex.get(name)
				}
		];
		final aliasNames = [for (name in importedTypeAliasIndex.keys()) name];
		aliasNames.sort((left, right) -> Reflect.compare(left, right));
		importedTypeAliases = [
			for (name in aliasNames)
				{
					local: name,
					qualified: importedTypeAliasIndex.get(name)
				}
		];
		usingTypeIdentities = orderedUsingTypeIdentities;

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(getSchemaRevision());
		identityFacts.push(programRevision);
		identityFacts.push(this.moduleRevision);
		identityFacts.push(this.moduleIdentity);
		identityFacts.push("local-types");
		identityFacts.push(Std.string(localTypeNames.length));
		for (fact in localTypeNames) {
			identityFacts.push(fact.source);
			identityFacts.push(fact.emitted);
		}
		identityFacts.push("imported-type-aliases");
		identityFacts.push(Std.string(importedTypeAliases.length));
		for (fact in importedTypeAliases) {
			identityFacts.push(fact.local);
			identityFacts.push(fact.qualified);
		}
		identityFacts.push("using-types");
		identityFacts.push(Std.string(usingTypeIdentities.length));
		for (identity in usingTypeIdentities)
			identityFacts.push(identity);
		canonicalIdentity = CompilerCacheIdentity.encode(identityFacts);
	}

	public function getProgramRevision():String
		return programRevision;

	public function getModuleRevision():String
		return moduleRevision;

	public function getModuleIdentity():String
		return moduleIdentity;

	public function getSchemaRevision():String
		return "php-module-render-facts-v2";

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function findLocalTypeName(name:String):Null<String> {
		if (name == null)
			return null;
		return localTypeNameIndex.get(PhpName.typeIdentifier(name));
	}

	public function findImportedTypeAlias(name:String):Null<String> {
		if (name == null)
			return null;
		return importedTypeAliasIndex.get(PhpName.typeIdentifier(name));
	}

	public function copyLocalTypeNames():Array<PhpModuleLocalTypeNameFact>
		return [for (fact in localTypeNames) {source: fact.source, emitted: fact.emitted}];

	public function copyImportedTypeAliases():Array<PhpModuleImportedTypeAliasFact>
		return [for (fact in importedTypeAliases) {local: fact.local, qualified: fact.qualified}];

	/** Return exact nominal types selected by module-level `using` directives. **/
	public function copyUsingTypeIdentities():Array<String>
		return usingTypeIdentities.copy();

	function addResolvedImport(directive:TyModuleDirective):Void {
		if (directive == null || !directive.getKind().match(TypeImport))
			return;
		for (provider in directive.getProviders()) {
			final rawImport = normalize(provider.getCanonicalName());
			final localName = directive.getImportedTypeLocalName(provider);
			if (localName == null || rawImport.length == 0)
				continue;
			final qualified = PhpRuntimeSupportTypeAlias.qualifiedName(rawImport);
			if (qualified != null)
				addExact(importedTypeAliasIndex, PhpName.typeIdentifier(localName), qualified, "imported alias", moduleIdentity);
		}
	}

	static function addExact(index:haxe.ds.StringMap<String>, key:String, value:String, kind:String, owner:String):Void {
		final normalizedKey = normalize(key);
		final normalizedValue = normalize(value);
		if (normalizedKey.length == 0 || normalizedValue.length == 0)
			throw "PHP module render facts contain an empty " + kind + " for " + owner;
		final previous = index.get(normalizedKey);
		if (previous == null)
			index.set(normalizedKey, normalizedValue);
		else if (previous != normalizedValue) {
			final first = Reflect.compare(previous, normalizedValue) <= 0 ? previous : normalizedValue;
			final second = first == previous ? normalizedValue : previous;
			throw "PHP module render facts assign conflicting "
				+ kind
				+ " "
				+ normalizedKey
				+ " in "
				+ owner
				+ ": "
				+ first
				+ " versus "
				+ second;
		}
	}

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
