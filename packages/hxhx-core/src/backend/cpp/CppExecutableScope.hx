package backend.cpp;

/**
	Bind local analysis to the exact function selected by the current program.
	Class-only syntax probes can have no program, but production lookups always
	carry one. Once bound, a scope cannot borrow another executable's catalogs.
**/
function bindFunctionFacts(scope:CppRenderScope, declaration:HxFunctionDecl):Void {
	if (scope == null || declaration == null)
		throw "C++ function local binding requires a scope and declaration";
	final lookup = scope.classLookup;
	if (lookup == null || lookup.typedProgram == null)
		return;
	final projection = lookup.typedProgram.requireFunction(scope.owner, declaration);
	if (scope.functionProjection != null && scope.functionProjection != projection)
		throw "C++ analysis scope is already bound to another function";
	if (scope.executableLocals != null) {
		if (scope.executableLocals.requireFunction() != projection)
			throw "C++ render scope is already bound to another function";
	}
	scope.functionProjection = projection;
}

/** Allocate output names only when a renderer requests an executable symbol plan. */
function bindFunction(scope:CppRenderScope, declaration:HxFunctionDecl, ?fixedSymbols:Array<String>):Void {
	bindFunctionFacts(scope, declaration);
	final lookup = scope.classLookup;
	if (lookup == null || lookup.typedProgram == null || scope.executableLocals != null)
		return;
	scope.executableLocals = lookup.typedProgram.functionLocals(scope.owner, declaration, fixedSymbols);
	scope.temporarySymbols = new CppTemporarySymbols(scope.executableLocals);
}

/** Keep a declared initializer's local ownership separate from constructor code. */
function bindInitializer(scope:CppRenderScope, declaration:HxFieldDecl, ?fixedSymbols:Array<String>):Void {
	if (scope == null || declaration == null)
		throw "C++ initializer local binding requires a scope and declaration";
	final lookup = scope.classLookup;
	if (lookup == null || lookup.typedProgram == null)
		return;
	final projection = lookup.typedProgram.requireInitializer(scope.owner, declaration);
	if (scope.functionProjection != null)
		throw "C++ function analysis cannot authorize an initializer";
	if (scope.executableLocals != null) {
		if (scope.executableLocals.requireInitializer() != projection)
			throw "C++ render scope is already bound to another initializer";
		return;
	}
	scope.executableLocals = lookup.typedProgram.initializerLocals(scope.owner, declaration, fixedSymbols);
	scope.temporarySymbols = new CppTemporarySymbols(scope.executableLocals);
}

/** Request target storage explicitly; an authored prefix never grants this role. */
function temporarySymbol(scope:CppRenderScope, preferred:String):String {
	if (scope == null || scope.executableLocals == null)
		return preferred;
	if (scope.temporarySymbols == null)
		throw "C++ executable scope has no temporary symbol owner";
	return scope.temporarySymbols.symbol(preferred);
}

/** A local miss may name a field only when the current executable selected that exact field. */
function findField(scope:CppRenderScope, name:String):Null<TyFieldInfo> {
	if (!hasCatalog(scope) || findLocal(scope, name) != null)
		return null;
	final fields = scope.functionProjection != null ? scope.functionProjection.getFieldReadCatalog() : scope.executableLocals.getFieldReadCatalog();
	final selected = fields.findByProjectedName(name);
	return selected == null ? null : selected.getField();
}

/** Analysis uses exact source identities even when no target symbol plan exists. */
function findLocal(scope:CppRenderScope, name:String):Null<TypedBackendLocalProjection> {
	if (scope == null)
		return null;
	if (scope.functionProjection != null)
		return scope.functionProjection.getLocalCatalog().findByProjectedName(name);
	return scope.executableLocals == null ? null : scope.executableLocals.findLocal(name);
}

/** A complete exact callable owns its storage type even when a later assigned body returns a narrower value. */
function hasSelectedCallable(scope:CppRenderScope, name:String):Bool {
	final selected = findLocal(scope, name);
	if (selected == null)
		return false;
	final type = selected.getBinding().getType();
	return type.isFunction() && !type.hasUnknownComponent();
}

function hasCatalog(scope:CppRenderScope):Bool
	return scope != null && (scope.functionProjection != null || scope.executableLocals != null);
