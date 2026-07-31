package backend.source;

typedef PhpProgramEnumConstructorFact = {
	final enumName:String;
	final constructorName:String;
	final hasArguments:Bool;
};

typedef PhpProgramEnumAbstractValueFact = {
	final typeName:String;
	final fieldName:String;
};

typedef PhpProgramOverloadMethodMap = haxe.ds.StringMap<haxe.ds.StringMap<Array<HxFunctionDecl>>>;

typedef PhpProgramModuleRenderInput = {
	final moduleIdentity:String;
	final facts:PhpModuleRenderFacts;
};

typedef PhpProgramLegacyRenderFacts = {
	final instanceMethodsByType:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;
	final instanceMethodArgumentsByType:haxe.ds.StringMap<haxe.ds.StringMap<Array<HxFunctionArg>>>;
	final instanceFieldsByType:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;
	final instanceFieldTypeHintsByType:haxe.ds.StringMap<haxe.ds.StringMap<String>>;
	final dynamicMethodsByType:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;
	final staticMethodsByType:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;
	final staticOverloadsByType:PhpProgramOverloadMethodMap;
	final instanceOverloadsByType:PhpProgramOverloadMethodMap;
	final genericStaticFunctionsByType:haxe.ds.StringMap<haxe.ds.StringMap<HxFunctionDecl>>;
	final staticCallableFieldsByType:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;
	final classBaseTypes:haxe.ds.StringMap<String>;
	final stringExtensionMethodsByClass:haxe.ds.StringMap<haxe.ds.StringMap<String>>;
	final enumConstructors:haxe.ds.StringMap<PhpProgramEnumConstructorFact>;
	final ambiguousEnumConstructors:haxe.ds.StringMap<Bool>;
	final enumConstructorsByEnum:haxe.ds.StringMap<haxe.ds.StringMap<PhpProgramEnumConstructorFact>>;
	final enumAbstractValues:haxe.ds.StringMap<PhpProgramEnumAbstractValueFact>;
	final ambiguousEnumAbstractValues:haxe.ds.StringMap<Bool>;
};

/**
	Request-owned PHP program and support-rendering state.

	The exact program/module facts and class graph identify the sealed typed
	input. The remaining compatibility catalogs preserve the established PHP
	target spelling and support-scaffolding behavior while that target logic is
	extracted from `SourceTargetCommon`; they are private to this one renderer
	and cannot be installed as process-wide current state.

	This owner deliberately does not call the shared syntax kernel. Keeping the
	dependency one-way lets `SourceTargetCommon` consume it without creating a
	generated OCaml module cycle.
**/
class PhpProgramBodyRenderer {
	final programFacts:PhpProgramRenderFacts;
	final moduleFactsByIdentity:haxe.ds.StringMap<PhpModuleRenderFacts>;
	final classGraph:TypedBackendClassGraph;
	final legacy:PhpProgramLegacyRenderFacts;

	public function new(programFacts:PhpProgramRenderFacts, modules:Array<PhpProgramModuleRenderInput>, classGraph:TypedBackendClassGraph,
			legacy:PhpProgramLegacyRenderFacts) {
		if (programFacts == null || classGraph == null || legacy == null)
			throw "PHP program renderer requires complete program facts";
		if (programFacts.getProgramRevision() != classGraph.getProgramRevision())
			throw "PHP program renderer received facts from different typed-program revisions";
		this.programFacts = programFacts;
		this.classGraph = classGraph;
		this.legacy = legacy;
		moduleFactsByIdentity = new haxe.ds.StringMap<PhpModuleRenderFacts>();
		if (modules == null || modules.length == 0)
			throw "PHP program renderer requires at least one exact module fact";
		for (input in modules) {
			if (input == null || input.facts == null)
				throw "PHP program renderer contains a null module fact";
			final moduleIdentity = normalize(input.moduleIdentity);
			if (moduleIdentity.length == 0 || input.facts.getModuleIdentity() != moduleIdentity)
				throw "PHP program renderer contains a mismatched module identity";
			if (input.facts.getProgramRevision() != programFacts.getProgramRevision())
				throw "PHP program renderer received module " + moduleIdentity + " from a different typed program";
			final previous = moduleFactsByIdentity.get(moduleIdentity);
			if (previous == null)
				moduleFactsByIdentity.set(moduleIdentity, input.facts);
			else if (previous.getCanonicalIdentity() != input.facts.getCanonicalIdentity())
				throw "PHP program renderer contains conflicting module facts for " + moduleIdentity;
		}
	}

	public function getProgramFacts():PhpProgramRenderFacts
		return programFacts;

	public function getClassGraph():TypedBackendClassGraph
		return classGraph;

	public function requireModuleFacts(moduleIdentity:String):PhpModuleRenderFacts {
		final normalized = normalize(moduleIdentity);
		final facts = moduleFactsByIdentity.get(normalized);
		if (facts == null)
			throw "PHP program renderer cannot find exact module facts for " + normalized;
		return facts;
	}

	public function isKnownType(name:String):Bool
		return programFacts.isKnownType(name);

	public function isAbstractType(name:String):Bool
		return programFacts.isAbstractType(name);

	public function findEmittedTypeName(name:String):Null<String>
		return programFacts.findEmittedTypeName(name);

	public function isDuplicateTypeName(name:String):Bool
		return programFacts.isDuplicateTypeName(name);

	public function isInterfaceTypeName(name:String):Bool
		return programFacts.isInterfaceTypeName(name);

	public function findLocalTypeName(moduleIdentity:String, name:String):Null<String>
		return requireModuleFacts(moduleIdentity).findLocalTypeName(name);

	public function findImportedTypeAlias(moduleIdentity:String, name:String):Null<String>
		return requireModuleFacts(moduleIdentity).findImportedTypeAlias(name);

	public function hasInstanceMethod(candidates:Array<String>, name:String):Bool {
		final methods = findInner(legacy.instanceMethodsByType, candidates);
		return methods != null && methods.exists(name);
	}

	public function findInstanceMethodArguments(candidates:Array<String>, name:String):Null<Array<HxFunctionArg>> {
		final methods = findInner(legacy.instanceMethodArgumentsByType, candidates);
		if (methods == null)
			return null;
		final arguments = methods.get(name);
		return arguments == null ? null : arguments.copy();
	}

	public function hasInstanceField(candidates:Array<String>, name:String):Bool {
		final fields = findInner(legacy.instanceFieldsByType, candidates);
		return fields != null && fields.exists(name);
	}

	public function findInstanceFieldType(candidates:Array<String>, name:String):Null<String> {
		final fields = findInner(legacy.instanceFieldTypeHintsByType, candidates);
		return fields == null ? null : fields.get(name);
	}

	public function copyInstanceFieldTypes(candidates:Array<String>):Null<haxe.ds.StringMap<String>> {
		final fields = findInner(legacy.instanceFieldTypeHintsByType, candidates);
		return fields == null ? null : copyStringMap(fields);
	}

	public function hasDynamicMethod(candidates:Array<String>, name:String):Bool {
		final methods = findInner(legacy.dynamicMethodsByType, candidates);
		return methods != null && methods.exists(name);
	}

	public function hasStaticMethod(candidates:Array<String>, name:String):Bool {
		final methods = findInner(legacy.staticMethodsByType, candidates);
		return methods != null && methods.exists(name);
	}

	public function findStaticOverloads(candidates:Array<String>, name:String):Null<Array<HxFunctionDecl>>
		return findOverloads(legacy.staticOverloadsByType, candidates, name);

	public function findInstanceOverloads(candidates:Array<String>, name:String):Null<Array<HxFunctionDecl>>
		return findOverloads(legacy.instanceOverloadsByType, candidates, name);

	public function findGenericStaticFunction(candidates:Array<String>, name:String):Null<HxFunctionDecl> {
		final methods = findInner(legacy.genericStaticFunctionsByType, candidates);
		return methods == null ? null : methods.get(name);
	}

	public function hasStaticCallableField(candidates:Array<String>, name:String):Bool {
		final fields = findInner(legacy.staticCallableFieldsByType, candidates);
		return fields != null && fields.exists(name);
	}

	public function findClassBaseType(candidates:Array<String>):Null<String> {
		for (candidate in candidates)
			if (candidate != null && legacy.classBaseTypes.exists(candidate))
				return legacy.classBaseTypes.get(candidate);
		return null;
	}

	public function findStringExtensionOwner(candidates:Array<String>, name:String):Null<String> {
		final methods = findInner(legacy.stringExtensionMethodsByClass, candidates);
		return methods == null ? null : methods.get(name);
	}

	public function findEnumConstructor(candidates:Array<String>):Null<PhpProgramEnumConstructorFact> {
		for (candidate in candidates) {
			if (candidate == null || legacy.ambiguousEnumConstructors.exists(candidate))
				continue;
			final fact = legacy.enumConstructors.get(candidate);
			if (fact != null)
				return copyEnumConstructor(fact);
		}
		return null;
	}

	public function hasEnumOwner(candidates:Array<String>):Bool {
		for (candidate in candidates)
			if (candidate != null && legacy.enumConstructorsByEnum.exists(candidate))
				return true;
		return false;
	}

	public function findEnumAbstractValue(candidates:Array<String>):Null<PhpProgramEnumAbstractValueFact> {
		for (candidate in candidates) {
			if (candidate == null || legacy.ambiguousEnumAbstractValues.exists(candidate))
				continue;
			final fact = legacy.enumAbstractValues.get(candidate);
			if (fact != null)
				return {typeName: fact.typeName, fieldName: fact.fieldName};
		}
		return null;
	}

	static function findOverloads(maps:PhpProgramOverloadMethodMap, candidates:Array<String>, name:String):Null<Array<HxFunctionDecl>> {
		final methods = findInner(maps, candidates);
		if (methods == null)
			return null;
		final overloads = methods.get(name);
		return overloads == null ? null : overloads.copy();
	}

	static function findInner<T>(maps:haxe.ds.StringMap<haxe.ds.StringMap<T>>, candidates:Array<String>):Null<haxe.ds.StringMap<T>> {
		if (maps == null || candidates == null)
			return null;
		for (candidate in candidates)
			if (candidate != null && maps.exists(candidate))
				return maps.get(candidate);
		return null;
	}

	static function copyStringMap<T>(source:haxe.ds.StringMap<T>):haxe.ds.StringMap<T> {
		final out = new haxe.ds.StringMap<T>();
		for (key in source.keys())
			out.set(key, source.get(key));
		return out;
	}

	static function copyEnumConstructor(fact:PhpProgramEnumConstructorFact):PhpProgramEnumConstructorFact
		return {
			enumName: fact.enumName,
			constructorName: fact.constructorName,
			hasArguments: fact.hasArguments
		};

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
