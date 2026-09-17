package backend.vm;

import haxe.ds.StringMap;
import TypedBackendClassSemanticFacts.TypedBackendNominalKind;

/** The exact class and typed body selected for one declared function. */
typedef NekoProjectedFunction = {
	final owner:TypedBackendClassProjection;
	final body:TypedBackendFunctionProjection;
	final nominalKind:TypedBackendNominalKind;
	final symbol:String;
};

/**
	Indexes the typed program before Neko chooses runtime names or call forms.

	Canonical class identities include their declaring module. Function keys are
	the opaque declaration identities selected by typing. Keeping these indexes
	separate from target spellings prevents same-named helpers from changing owner
	during reachability or emission. Missing semantic facts fail at construction.
**/
class NekoTypedProgramProjection {
	public final classGraph:TypedBackendClassGraph;

	final classes = new StringMap<TypedBackendClassProjection>();
	final classIdentities = new haxe.ds.ObjectMap<HxClassDecl, String>();
	final functions = new StringMap<NekoProjectedFunction>();
	final functionDeclarations = new haxe.ds.ObjectMap<HxFunctionDecl, String>();
	final initializers = new haxe.ds.ObjectMap<HxFieldDecl, TypedBackendFieldInitializerProjection>();
	final symbols = new StringMap<String>();
	final occupiedNames = new StringMap<Bool>();
	final catchCatalogs = new StringMap<NekoCatchCatalog>();

	public function new(programRevision:String, modules:Array<TypedBackendModuleProjection>) {
		final classFacts = new Array<TypedBackendClassSemanticFacts>();
		for (module in modules) {
			for (owner in module.getClasses()) {
				final facts = owner.requireSemanticFacts();
				final identity = facts.getClassIdentity();
				if (classes.exists(identity))
					throw "Neko typed program contains duplicate class " + identity;
				classes.set(identity, owner);
				classIdentities.set(owner.getDeclaration(), identity);
				classFacts.push(facts);
				for (field in facts.copyFields())
					occupiedNames.set(field.name, true);
				for (method in facts.copyMethods())
					occupiedNames.set(method.name, true);
				for (initializer in owner.getFieldInitializers()) {
					final field = initializer.getField();
					if (field.getOwner().getCanonicalName() != identity || facts.findField(field.getCanonicalKey()) == null)
						throw "Neko typed program initializer has a different field owner: " + initializer.getStableIdentity();
					if (initializers.exists(initializer.getDeclaration()))
						throw "Neko typed program contains duplicate field initializer " + initializer.getStableIdentity();
					initializers.set(initializer.getDeclaration(), initializer);
					for (local in initializer.getLocalCatalog().getEntries())
						occupiedNames.set(local.getProjectedName(), true);
				}
				for (body in owner.getFunctions()) {
					for (local in body.getLocalCatalog().getEntries())
						occupiedNames.set(local.getProjectedName(), true);
					final declaration = body.getStableIdentity();
					final method = facts.findMethod(declaration);
					if (method == null)
						throw "Neko typed program cannot find declaration " + declaration + " in " + identity;
					final constructorCompletion = method.name == "new"
						&& !method.isStatic
						&& method.returnSemanticType.getNominalIdentity() != null
						&& method.returnSemanticType.getNominalIdentity().getCanonicalName() == identity
						&& body.getReturnType().getSemanticKey() == TyType.fromHintText("Void").getSemanticKey();
					if (method.name != HxFunctionDecl.getName(body.getDeclaration())
						|| method.isStatic != HxFunctionDecl.getIsStatic(body.getDeclaration())
						|| (!constructorCompletion && method.returnTypeIdentity != body.getReturnType().getSemanticKey()))
						throw "Neko typed program has conflicting function facts for " + declaration;
					if (functions.exists(declaration))
						throw "Neko typed program contains duplicate function " + declaration;
					final symbol = "__hxhx_exact_" + haxe.crypto.Sha256.encode(declaration);
					if (symbols.exists(symbol) && symbols.get(symbol) != declaration)
						throw "Neko exact declaration symbol collision for " + declaration;
					symbols.set(symbol, declaration);
					functionDeclarations.set(body.getDeclaration(), declaration);
					functions.set(declaration, {
						owner: owner,
						body: body,
						nominalKind: facts.getNominalKind(),
						symbol: symbol
					});
				}
			}
		}
		classGraph = new TypedBackendClassGraph(programRevision, classFacts);
		for (module in modules)
			for (owner in module.getClasses()) {
				for (fn in owner.getFunctions())
					catchCatalogs.set(fn.getStableIdentity(), new NekoCatchCatalog(this, FunctionBody(requireDeclaredFunction(fn.getDeclaration()))));
				for (initializer in owner.getFieldInitializers())
					catchCatalogs.set(initializer.getStableIdentity(), new NekoCatchCatalog(this, FieldInitializer(initializer)));
			}
	}

	/** Resolve the occurrence catalog only after verifying the exact executable object. */
	public function requireCatchCatalog(selected:Null<NekoExecutableProjection>):NekoCatchCatalog {
		if (selected == null)
			throw "Neko catch planning requires an exact current executable";
		final owner = switch (selected) {
			case FunctionBody(fn):
				final current = requireDeclaredFunction(fn.body.getDeclaration());
				if (current.body != fn.body || current.owner != fn.owner)
					throw "Neko catch planning received a foreign function projection";
				{identity: current.body.getStableIdentity(), revision: current.body.getBodyRevision()};
			case FieldInitializer(initializer):
				if (requireDeclaredInitializer(initializer.getDeclaration()) != initializer)
					throw "Neko catch planning received a foreign initializer projection";
				{identity: initializer.getStableIdentity(), revision: initializer.getBodyRevision()};
		};
		final catalog = catchCatalogs.get(owner.identity);
		if (catalog == null)
			throw "Neko catch planning lost its executable catalog";
		catalog.assertOwner(owner.identity, owner.revision);
		return catalog;
	}

	/** Projected declaration identity joins runtime spellings to canonical secondary-type owners. */
	public function requireClassIdentity(declaration:HxClassDecl):String {
		final identity = classIdentities.get(declaration);
		if (identity == null)
			throw "Neko typed program cannot identify projected class " + HxClassDecl.getName(declaration);
		return identity;
	}

	/** Existing generated declarations must not shadow an exact helper symbol. */
	public function reserveGeneratedSymbols(reserved:Array<String>):Void {
		for (symbol in reserved) {
			occupiedNames.set(symbol, true);
			if (symbols.exists(symbol))
				throw "Neko exact declaration symbol conflicts with generated symbol " + symbol;
		}
	}

	/** Choose an internal helper or instance-slot name after reserving all projected member and local names. */
	public function runtimeHelperName(base:String):String {
		var name = base;
		var suffix = 0;
		while (occupiedNames.exists(name))
			name = base + "_" + ++suffix;
		return name;
	}

	/** Choose a shared helper table name that no projected local or generated function can shadow. */
	public function exactHelperTableName():String {
		final base = "__hxhx_exact_helpers";
		var name = base;
		var suffix = 0;
		while (occupiedNames.exists(name))
			name = base + "_" + ++suffix;
		return name;
	}

	/** One receiver spelling stays distinct from every projected constructor and method local. */
	public function constructionReceiverName():String {
		final base = "__hxhx_self";
		var name = base;
		var suffix = 0;
		while (occupiedNames.exists(name))
			name = base + "_" + ++suffix;
		return name;
	}

	/** Selects a canonical class without package-name or short-name fallback. */
	public function requireClass(identity:String):TypedBackendClassProjection {
		final owner = classes.get(identity);
		if (owner == null)
			throw "Neko typed program cannot find class " + identity;
		return owner;
	}

	/**
		Selects the typed body for the exact declaration object being rendered.

		A matching name or signature from another projection cannot supply local
		bindings or a body revision for this program's catch and function plans.
	**/
	public function requireDeclaredFunction(declaration:HxFunctionDecl):NekoProjectedFunction {
		if (declaration == null)
			throw "Neko typed program cannot identify projected function <null>";
		final identity = functionDeclarations.get(declaration);
		if (identity == null)
			throw "Neko typed program cannot identify projected function " + HxFunctionDecl.getName(declaration);
		final selected = functions.get(identity);
		if (selected == null || selected.body.getDeclaration() != declaration)
			throw "Neko typed program lost projected function " + identity;
		return requireFunction(selected.owner.requireSemanticFacts().getClassIdentity(), identity);
	}

	/** Same-named fields from another projection cannot supply this program's initializer catalog. */
	public function requireDeclaredInitializer(declaration:HxFieldDecl):TypedBackendFieldInitializerProjection {
		final selected = declaration == null ? null : initializers.get(declaration);
		if (selected == null || selected.getDeclaration() != declaration)
			throw "Neko typed program cannot identify projected initializer";
		return selected;
	}

	/** Requires the selected declaration to belong to the selected exact owner. */
	public function requireFunction(ownerIdentity:String, declarationIdentity:String):NekoProjectedFunction {
		final owner = requireClass(ownerIdentity);
		final selected = functions.get(declarationIdentity);
		if (selected == null)
			throw "Neko typed program cannot find function " + declarationIdentity;
		if (selected.owner != owner)
			throw "Neko typed program function " + declarationIdentity + " does not belong to " + ownerIdentity;
		return {
			owner: selected.owner,
			body: selected.body,
			nominalKind: selected.nominalKind,
			symbol: selected.symbol
		};
	}
}
