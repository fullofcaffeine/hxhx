package backend.source;

import haxe.ds.StringMap;

typedef PhpFunctionLocalFact = {
	final projectedName:String;
	final targetName:String;
	final bindingIdentity:String;
	final sourceName:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
	final declarationKind:TyLocalDeclarationKind;
};

/**
	Immutable PHP view of the exact locals owned by one typed function.

	The catalog's projected name is a transport label only; the binding still
	owns semantic identity and type. This adapter canonicalizes the type selected
	by shared typing and returns fresh maps so nested PHP scopes can mutate their
	own copies without changing the typed projection.
**/
class PhpFunctionLocalFacts {
	final locals:Array<PhpFunctionLocalFact>;
	final typeHints:StringMap<String>;

	public function new(projection:Null<TypedBackendFunctionProjection>, normalizeName:String->String, ?initializerCatalog:TypedBackendLocalCatalog) {
		if (projection == null && initializerCatalog == null)
			throw "PHP local facts require an exact typed executable projection";
		if (projection != null && initializerCatalog != null)
			throw "PHP local facts cannot combine function and field-initializer catalogs";
		if (normalizeName == null)
			throw "PHP local facts require a target-name normalizer";
		final catalog = projection == null ? initializerCatalog : projection.getLocalCatalog();
		locals = [];
		typeHints = new StringMap<String>();
		for (local in catalog.getEntries()) {
			final projectedName = local.getProjectedName();
			final targetName = normalizeName(projectedName);
			if (targetName == null || targetName.length == 0)
				throw "PHP local facts produced an empty target name for " + projectedName;
			final binding = local.getBinding();
			final semanticType = binding.getType();
			final typeHint = semanticType.isUnknown() || semanticType.isNoNormalCompletion() ? "" : semanticType.getCanonicalDisplay();
			if (typeHints.exists(targetName) && typeHints.get(targetName) != typeHint)
				throw "PHP local facts contain conflicting types for target local " + targetName;
			for (fact in locals)
				if (fact.targetName == targetName && fact.bindingIdentity != binding.getIdentity().getCanonicalKey())
					throw "PHP local facts contain conflicting exact locals for target name " + targetName;
			locals.push({
				projectedName: projectedName,
				targetName: targetName,
				bindingIdentity: binding.getIdentity().getCanonicalKey(),
				sourceName: binding.getSourceName(),
				semanticType: semanticType,
				typeIdentity: semanticType.getSemanticKey(),
				typeDisplay: semanticType.getCanonicalDisplay(),
				declarationKind: binding.getKind()
			});
			typeHints.set(targetName, typeHint);
		}
		locals.sort((left, right) -> Reflect.compare(left.bindingIdentity, right.bindingIdentity));
	}

	/** Build the same immutable local view for a typed field initializer. **/
	public static function fromCatalog(catalog:TypedBackendLocalCatalog, normalizeName:String->String):PhpFunctionLocalFacts
		return new PhpFunctionLocalFacts(null, normalizeName, catalog);

	/** Return exact typed locals without exposing the record's owned array. **/
	public function copyLocals():Array<PhpFunctionLocalFact>
		return [for (fact in locals) copyLocal(fact)];

	public function copyTypeHints():StringMap<String> {
		final copy = new StringMap<String>();
		for (name => typeHint in typeHints)
			copy.set(name, typeHint);
		return copy;
	}

	static function copyLocal(fact:PhpFunctionLocalFact):PhpFunctionLocalFact
		return {
			projectedName: fact.projectedName,
			targetName: fact.targetName,
			bindingIdentity: fact.bindingIdentity,
			sourceName: fact.sourceName,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			declarationKind: fact.declarationKind
		};
}
