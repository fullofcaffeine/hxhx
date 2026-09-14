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
	final classes = new StringMap<TypedBackendClassProjection>();
	final functions = new StringMap<NekoProjectedFunction>();
	final symbols = new StringMap<String>();
	final occupiedNames = new StringMap<Bool>();

	public function new(modules:Array<TypedBackendModuleProjection>) {
		for (module in modules) {
			for (owner in module.getClasses()) {
				final facts = owner.requireSemanticFacts();
				final identity = facts.getClassIdentity();
				if (classes.exists(identity))
					throw "Neko typed program contains duplicate class " + identity;
				classes.set(identity, owner);
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
					functions.set(declaration, {
						owner: owner,
						body: body,
						nominalKind: facts.getNominalKind(),
						symbol: symbol
					});
				}
			}
		}
	}

	/** Existing generated declarations must not shadow an exact helper symbol. */
	public function reserveGeneratedSymbols(reserved:Array<String>):Void {
		for (symbol in reserved) {
			occupiedNames.set(symbol, true);
			if (symbols.exists(symbol))
				throw "Neko exact declaration symbol conflicts with generated symbol " + symbol;
		}
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

	/** Selects a canonical class without package-name or short-name fallback. */
	public function requireClass(identity:String):TypedBackendClassProjection {
		final owner = classes.get(identity);
		if (owner == null)
			throw "Neko typed program cannot find class " + identity;
		return owner;
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
