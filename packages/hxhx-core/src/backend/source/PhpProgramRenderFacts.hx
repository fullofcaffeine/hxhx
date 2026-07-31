package backend.source;

typedef PhpEmittedTypeNameFact = {
	final lookup:String;
	final emitted:String;
};

typedef PhpProgramRenderModuleInput = {
	final moduleIdentity:String;
	final projection:TypedBackendModuleProjection;
};

private typedef PhpProjectedTypeFact = {
	final identity:String;
	final moduleIdentity:String;
	final packagePath:String;
	final moduleName:String;
	final rawName:String;
	final shortName:String;
	final isAbstract:Bool;
	final isInterface:Bool;
};

private typedef PhpEmittedTypeNameCandidate = {
	final emitted:String;
	final type:PhpProjectedTypeFact;
	final exact:Bool;
};

/**
	Immutable PHP naming facts for one exact sealed typed program.

	Request-owned function renderers consume this record for exact type spelling.
	The older program and support-scaffolding path still mirrors equivalent
	tables in mutable static fields until Slice 4; those fields are not an
	alternate function-state source.

	The exact target-neutral program revision identifies the semantic input.
	The schema revision separately identifies these PHP-specific spelling rules.
	Neither value is a persistent cache digest.
**/
class PhpProgramRenderFacts {
	final programRevision:String;
	final knownTypeNames:Array<String>;
	final abstractTypeNames:Array<String>;
	final emittedTypeNames:Array<PhpEmittedTypeNameFact>;
	final duplicateTypeNames:Array<String>;
	final interfaceTypeNames:Array<String>;
	final knownTypeNameIndex:haxe.ds.StringMap<Bool>;
	final abstractTypeNameIndex:haxe.ds.StringMap<Bool>;
	final emittedTypeNameIndex:haxe.ds.StringMap<String>;
	final duplicateTypeNameIndex:haxe.ds.StringMap<Bool>;
	final interfaceTypeNameIndex:haxe.ds.StringMap<Bool>;
	final canonicalIdentity:String;

	public function new(programRevision:String, modules:Array<PhpProgramRenderModuleInput>) {
		this.programRevision = normalize(programRevision);
		if (this.programRevision.length == 0)
			throw "PHP program render facts require an exact typed-program revision";

		final typesByIdentity = new haxe.ds.StringMap<PhpProjectedTypeFact>();
		if (modules != null)
			for (moduleInput in modules) {
				if (moduleInput == null || moduleInput.projection == null)
					throw "PHP program render facts contain a null module projection";
				final moduleIdentity = normalize(moduleInput.moduleIdentity);
				if (moduleIdentity.length == 0)
					throw "PHP program render facts require an exact module identity";
				final moduleName = moduleIdentity.indexOf(".") < 0 ? moduleIdentity : moduleIdentity.substr(moduleIdentity.lastIndexOf(".") + 1);
				final declaration = moduleInput.projection.getDeclaration();
				final packagePath = normalize(HxModuleDecl.getPackagePath(declaration));
				for (projectedClass in moduleInput.projection.getClasses()) {
					if (projectedClass == null)
						throw "PHP program render facts contain a null class projection";
					final cls = projectedClass.getDeclaration();
					final rawName = normalize(HxClassDecl.getName(cls));
					final identity = CompilerCacheIdentity.encode(["php-projected-type-v1", moduleIdentity, rawName]);
					final fact:PhpProjectedTypeFact = {
						identity: identity,
						moduleIdentity: moduleIdentity,
						packagePath: packagePath,
						moduleName: moduleName,
						rawName: rawName,
						shortName: PhpName.typeIdentifier(rawName),
						isAbstract: hasAbstractMarker(cls),
						isInterface: HxClassDecl.getIsInterface(cls)
					};
					final previous = typesByIdentity.get(identity);
					if (previous == null)
						typesByIdentity.set(identity, fact);
					else if (!sameProjectedType(previous, fact))
						throw "PHP program render facts contain conflicting projected type " + qualifiedModuleType(fact);
				}
			}

		final typeIdentities = [for (identity in typesByIdentity.keys()) identity];
		typeIdentities.sort((left, right) -> Reflect.compare(left, right));
		final types = [for (identity in typeIdentities) typesByIdentity.get(identity)];

		final shortNameCounts = new haxe.ds.StringMap<Int>();
		for (type in types)
			shortNameCounts.set(type.shortName, shortNameCounts.exists(type.shortName) ? shortNameCounts.get(type.shortName) + 1 : 1);

		knownTypeNameIndex = new haxe.ds.StringMap<Bool>();
		abstractTypeNameIndex = new haxe.ds.StringMap<Bool>();
		emittedTypeNameIndex = new haxe.ds.StringMap<String>();
		duplicateTypeNameIndex = new haxe.ds.StringMap<Bool>();
		interfaceTypeNameIndex = new haxe.ds.StringMap<Bool>();
		final emittedCandidates = new haxe.ds.StringMap<Array<PhpEmittedTypeNameCandidate>>();
		final emittedTypeOwners = new haxe.ds.StringMap<PhpProjectedTypeFact>();

		for (name in [
			"Int",
			"String",
			"Bool",
			"Float",
			"Array",
			"Class",
			"Enum",
			"Dynamic",
			"Date",
			"Math",
			"Xml",
			"haxe.ds.StringMap",
			"haxe.ds.List",
			"List"
		])
			addSourceTypeSpellings(knownTypeNameIndex, name);

		for (shortName in shortNameCounts.keys())
			if (shortNameCounts.get(shortName) > 1)
				duplicateTypeNameIndex.set(shortName, true);

		for (type in types) {
			addSourceTypeSpellings(knownTypeNameIndex, type.rawName);
			if (type.packagePath.length > 0)
				addSourceTypeSpellings(knownTypeNameIndex, type.packagePath + "." + type.rawName);
			if (type.isAbstract) {
				addSourceTypeSpellings(abstractTypeNameIndex, type.rawName);
				if (type.packagePath.length > 0)
					addSourceTypeSpellings(abstractTypeNameIndex, type.packagePath + "." + type.rawName);
			}

			final emittedName = emittedNameFor(type, duplicateTypeNameIndex.exists(type.shortName));
			final emittedIdentity = emittedName.toLowerCase();
			final previousEmittedOwner = emittedTypeOwners.get(emittedIdentity);
			if (previousEmittedOwner == null)
				emittedTypeOwners.set(emittedIdentity, type);
			else if (previousEmittedOwner.identity != type.identity)
				throw "PHP program render facts assign emitted type " + emittedName + " to both " + qualifiedModuleType(previousEmittedOwner) + " and "
					+ qualifiedModuleType(type);
			final fullName = type.packagePath.length == 0 ? type.rawName : type.packagePath + "." + type.rawName;
			final exactTypeName = qualifiedModuleType(type);
			final genericKeys = [type.rawName, type.shortName, fullName, PhpName.typePath(fullName)];
			final includeShortName = shortNameCounts.get(type.shortName) == 1;
			for (key in genericKeys) {
				final clean = normalize(key);
				if (clean.length == 0)
					continue;
				if ((clean == type.rawName || clean == type.shortName) && !includeShortName)
					continue;
				addEmittedCandidate(emittedCandidates, clean, emittedName, type, clean == fullName && type.rawName == type.moduleName);
			}
			addEmittedCandidate(emittedCandidates, exactTypeName, emittedName, type, true);
			addEmittedCandidate(emittedCandidates, emittedName, emittedName, type, true);
			if (type.moduleName.length > 0 && type.rawName != type.moduleName) {
				final moduleLocalType = type.moduleName + "." + type.rawName;
				addEmittedCandidate(emittedCandidates, moduleLocalType, emittedName, type, type.packagePath.length == 0);
			}
			if (type.isInterface)
				interfaceTypeNameIndex.set(emittedName, true);
		}
		resolveEmittedCandidates(emittedCandidates);

		knownTypeNames = sortedBoolKeys(knownTypeNameIndex);
		abstractTypeNames = sortedBoolKeys(abstractTypeNameIndex);
		duplicateTypeNames = sortedBoolKeys(duplicateTypeNameIndex);
		interfaceTypeNames = sortedBoolKeys(interfaceTypeNameIndex);
		final emittedLookups = [for (lookup in emittedTypeNameIndex.keys()) lookup];
		emittedLookups.sort((left, right) -> Reflect.compare(left, right));
		emittedTypeNames = [
			for (lookup in emittedLookups)
				{
					lookup: lookup,
					emitted: emittedTypeNameIndex.get(lookup)
				}
		];

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(getSchemaRevision());
		identityFacts.push(this.programRevision);
		addIdentitySection(identityFacts, "known", knownTypeNames);
		addIdentitySection(identityFacts, "abstract", abstractTypeNames);
		identityFacts.push("emitted");
		identityFacts.push(Std.string(emittedTypeNames.length));
		for (fact in emittedTypeNames) {
			identityFacts.push(fact.lookup);
			identityFacts.push(fact.emitted);
		}
		addIdentitySection(identityFacts, "duplicate", duplicateTypeNames);
		addIdentitySection(identityFacts, "interface", interfaceTypeNames);
		canonicalIdentity = CompilerCacheIdentity.encode(identityFacts);
	}

	/** Return the exact target-neutral program revision that these facts describe. **/
	public function getProgramRevision():String
		return programRevision;

	/** Return the version of the PHP-specific spelling and lookup rules. **/
	public function getSchemaRevision():String
		return "php-program-render-facts-v1";

	/** Return the deterministic in-memory identity of the complete fact record. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function isKnownType(name:String):Bool
		return knownTypeNameIndex.exists(name);

	public function isAbstractType(name:String):Bool
		return abstractTypeNameIndex.exists(name);

	public function findEmittedTypeName(name:String):Null<String>
		return emittedTypeNameIndex.get(name);

	public function isDuplicateTypeName(name:String):Bool
		return duplicateTypeNameIndex.exists(name);

	public function isInterfaceTypeName(name:String):Bool
		return interfaceTypeNameIndex.exists(name);

	public function copyKnownTypeNames():Array<String>
		return knownTypeNames.copy();

	public function copyAbstractTypeNames():Array<String>
		return abstractTypeNames.copy();

	public function copyEmittedTypeNames():Array<PhpEmittedTypeNameFact>
		return [for (fact in emittedTypeNames) {lookup: fact.lookup, emitted: fact.emitted}];

	public function copyDuplicateTypeNames():Array<String>
		return duplicateTypeNames.copy();

	public function copyInterfaceTypeNames():Array<String>
		return interfaceTypeNames.copy();

	static function hasAbstractMarker(cls:HxClassDecl):Bool {
		for (metadata in HxClassDecl.getMetadata(cls))
			if (metadata == "__hxhx_abstract")
				return true;
		return false;
	}

	static function sameProjectedType(left:PhpProjectedTypeFact, right:PhpProjectedTypeFact):Bool
		return left.moduleIdentity == right.moduleIdentity
			&& left.packagePath == right.packagePath
			&& left.moduleName == right.moduleName
			&& left.rawName == right.rawName
			&& left.shortName == right.shortName
			&& left.isAbstract == right.isAbstract
			&& left.isInterface == right.isInterface;

	static function qualifiedModuleType(type:PhpProjectedTypeFact):String {
		return type.rawName == type.moduleName ? type.moduleIdentity : type.moduleIdentity + "." + type.rawName;
	}

	static function emittedNameFor(type:PhpProjectedTypeFact, duplicateShortName:Bool):String {
		if (!duplicateShortName || type.moduleName.length == 0 || type.rawName == type.moduleName)
			return type.shortName;
		return PhpName.typeIdentifier(PhpName.typeIdentifier(type.moduleName) + "_" + type.shortName);
	}

	static function addSourceTypeSpellings(out:haxe.ds.StringMap<Bool>, name:String):Void {
		if (name == null || name.length == 0)
			return;
		out.set(name, true);
		out.set(SourceIdentifier.sanitize(name), true);
		final parts = name.split(".");
		if (parts.length > 0) {
			final shortName = parts[parts.length - 1];
			out.set(shortName, true);
			out.set(SourceIdentifier.sanitize(shortName), true);
		}
	}

	static function addEmittedCandidate(out:haxe.ds.StringMap<Array<PhpEmittedTypeNameCandidate>>, lookup:String, emitted:String, type:PhpProjectedTypeFact,
			exact:Bool):Void {
		final clean = normalize(lookup);
		if (clean.length == 0)
			return;
		final candidate:PhpEmittedTypeNameCandidate = {emitted: emitted, type: type, exact: exact};
		final previous = out.get(clean);
		if (previous == null)
			out.set(clean, [candidate]);
		else
			previous.push(candidate);
	}

	function resolveEmittedCandidates(candidates:haxe.ds.StringMap<Array<PhpEmittedTypeNameCandidate>>):Void {
		final lookups = [for (lookup in candidates.keys()) lookup];
		lookups.sort((left, right) -> Reflect.compare(left, right));
		for (lookup in lookups) {
			final values = candidates.get(lookup);
			final exactEmitted = new haxe.ds.StringMap<PhpProjectedTypeFact>();
			final allEmitted = new haxe.ds.StringMap<PhpProjectedTypeFact>();
			for (candidate in values) {
				allEmitted.set(candidate.emitted, candidate.type);
				if (candidate.exact)
					exactEmitted.set(candidate.emitted, candidate.type);
			}
			final exactNames = [for (emitted in exactEmitted.keys()) emitted];
			exactNames.sort((left, right) -> Reflect.compare(left, right));
			if (exactNames.length > 1) {
				final first = exactEmitted.get(exactNames[0]);
				final second = exactEmitted.get(exactNames[1]);
				throw "PHP program render facts assign conflicting emitted names to "
					+ lookup
					+ ": "
					+ exactNames[0]
					+ " for "
					+ qualifiedModuleType(first)
					+ " and "
					+ exactNames[1]
					+ " for "
					+ qualifiedModuleType(second);
			}
			if (exactNames.length == 1) {
				emittedTypeNameIndex.set(lookup, exactNames[0]);
				continue;
			}
			final names = [for (emitted in allEmitted.keys()) emitted];
			names.sort((left, right) -> Reflect.compare(left, right));
			if (names.length == 1)
				emittedTypeNameIndex.set(lookup, names[0]);
		}
	}

	static function sortedBoolKeys(values:haxe.ds.StringMap<Bool>):Array<String> {
		final out = [for (value in values.keys()) value];
		out.sort((left, right) -> Reflect.compare(left, right));
		return out;
	}

	static function addIdentitySection(out:Array<Null<String>>, label:String, values:Array<String>):Void {
		out.push(label);
		out.push(Std.string(values.length));
		for (value in values)
			out.push(value);
	}

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
