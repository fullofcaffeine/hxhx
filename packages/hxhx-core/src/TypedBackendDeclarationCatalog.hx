/** One exact function declaration and the constructor facts produced with its body. */
typedef TypedBackendFunctionDeclarationEntry = {
	final backendClass:HxClassDecl;
	final backendFunction:HxFunctionDecl;
	final stableIdentity:String;
	final bodyRevision:String;
	final constructorCatalog:TypedBackendConstructorCatalog;
}

/**
	Own the legacy backend declaration together with exact function identities.

	`TypedBodySource` creates both the source-shaped declaration objects and
	their stable typed identities in one operation. A migrated backend can hand
	an exact class/function object back to `TypedModule`, which resolves it
	without source positions, names, sanitized spellings, or traversal indexes.
**/
class TypedBackendDeclarationCatalog {
	final declaration:HxModuleDecl;
	final runtimeTypeCatalogs:Array<TypedBackendRuntimeTypeCatalog>;
	final initializers:Array<TypedBackendFieldInitializerProjection>;
	final functions:Array<TypedBackendFunctionDeclarationEntry>;

	public function new(declaration:HxModuleDecl, functions:Array<TypedBackendFunctionDeclarationEntry>,
			?runtimeTypeCatalogs:Array<TypedBackendRuntimeTypeCatalog>, ?initializers:Array<TypedBackendFieldInitializerProjection>) {
		if (declaration == null)
			throw "typed backend declaration catalog requires a module declaration";
		this.declaration = declaration;
		this.functions = functions == null ? [] : functions.copy();
		this.runtimeTypeCatalogs = runtimeTypeCatalogs == null ? [] : runtimeTypeCatalogs.copy();
		this.initializers = initializers == null ? [] : initializers.copy();
		final classes = HxModuleDecl.getClasses(declaration);
		final constructions = constructorExpressions();
		var count = 0;
		final seenFunctions = new Array<HxFunctionDecl>();
		for (entry in this.functions) {
			if (classes.indexOf(entry.backendClass) < 0
				|| HxClassDecl.getFunctions(entry.backendClass).indexOf(entry.backendFunction) < 0
				|| seenFunctions.indexOf(entry.backendFunction) >= 0)
				throw "declaration catalog contains a foreign or repeated function";
			seenFunctions.push(entry.backendFunction);
			entry.constructorCatalog.assertOwner(entry.stableIdentity, entry.bodyRevision);
			entry.constructorCatalog.assertExpressions(TypedConstructorSource.inStatements(HxFunctionDecl.getBody(entry.backendFunction)));
			count += entry.constructorCatalog.getEntries().length;
		}
		final seenFields = new Array<HxFieldDecl>();
		for (initializer in this.initializers) {
			var present = false;
			for (cls in classes)
				if (HxClassDecl.getFields(cls).indexOf(initializer.getDeclaration()) >= 0)
					present = true;
			if (!present || seenFields.indexOf(initializer.getDeclaration()) >= 0)
				throw "declaration catalog contains a foreign or repeated initializer";
			seenFields.push(initializer.getDeclaration());
			initializer.getConstructorCatalog().assertExpressions(TypedConstructorSource.inExpression(initializer.getExpression()));
			count += initializer.getConstructorCatalog().getEntries().length;
		}
		if (constructions.length != count)
			throw "declaration catalog lost constructor occurrences";
	}

	public function getDeclaration():HxModuleDecl
		return declaration;

	/** Resolve constructor facts from this declaration view, never from a separately rebuilt strict projection. */
	public function requireConstructor(expression:HxExpr):TypedBackendConstructorOccurrence {
		final classes = HxModuleDecl.getClasses(declaration);
		var selected:Null<TypedBackendConstructorOccurrence> = null;
		for (entry in functions) {
			if (classes.indexOf(entry.backendClass) >= 0
				&& HxClassDecl.getFunctions(entry.backendClass).indexOf(entry.backendFunction) >= 0
				&& TypedConstructorSource.inStatements(HxFunctionDecl.getBody(entry.backendFunction)).indexOf(expression) >= 0) {
				if (selected != null)
					throw "declaration projection repeats a constructor occurrence";
				selected = entry.constructorCatalog.require(expression, entry.stableIdentity, entry.bodyRevision);
			}
		}
		for (initializer in initializers)
			for (cls in classes)
				if (HxClassDecl.getFields(cls).indexOf(initializer.getDeclaration()) >= 0
					&& TypedConstructorSource.inExpression(initializer.getExpression()).indexOf(expression) >= 0) {
					if (selected != null)
						throw "declaration projection repeats a constructor occurrence";
					selected = initializer.requireConstructor(expression);
				}
		if (selected == null)
			throw "constructor is absent from the current declaration projection";
		return selected;
	}

	function constructorExpressions():Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (cls in HxModuleDecl.getClasses(declaration)) {
			for (fn in HxClassDecl.getFunctions(cls))
				for (expression in TypedConstructorSource.inStatements(HxFunctionDecl.getBody(fn)))
					out.push(expression);
			for (field in HxClassDecl.getFields(cls))
				for (expression in TypedConstructorSource.inExpression(HxFieldDecl.getInit(field)))
					out.push(expression);
		}
		return out;
	}

	/** Declaration-only consumers cannot interpret executable-owned type operands. */
	public function assertRuntimeTypeOperandsAbsent():Void {
		for (catalog in runtimeTypeCatalogs)
			catalog.assertUnsupportedAbsent("declaration-only backend");
	}

	/** Resolve one exact declaration pair to the stable typed function identity created with it. **/
	public function findFunctionIdentity(backendClass:HxClassDecl, backendFunction:HxFunctionDecl):Null<String> {
		for (entry in functions)
			if (entry.backendClass == backendClass && entry.backendFunction == backendFunction)
				return entry.stableIdentity;
		return null;
	}
}
