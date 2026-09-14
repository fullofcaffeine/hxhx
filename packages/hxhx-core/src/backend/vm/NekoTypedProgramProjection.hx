package backend.vm;

import haxe.ds.StringMap;

/** The exact class and typed body selected for one declared function. */
typedef NekoProjectedFunction = {
	final owner:TypedBackendClassProjection;
	final body:TypedBackendFunctionProjection;
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

	public function new(modules:Array<TypedBackendModuleProjection>) {
		for (module in modules) {
			for (owner in module.getClasses()) {
				final facts = owner.requireSemanticFacts();
				final identity = facts.getClassIdentity();
				if (classes.exists(identity))
					throw "Neko typed program contains duplicate class " + identity;
				classes.set(identity, owner);
				for (body in owner.getFunctions()) {
					final declaration = body.getStableIdentity();
					final method = facts.findMethod(declaration);
					if (method == null)
						throw "Neko typed program cannot find declaration " + declaration + " in " + identity;
					if (method.name != HxFunctionDecl.getName(body.getDeclaration())
						|| method.isStatic != HxFunctionDecl.getIsStatic(body.getDeclaration())
						|| method.returnTypeIdentity != body.getReturnType().getSemanticKey())
						throw "Neko typed program has conflicting function facts for " + declaration;
					if (functions.exists(declaration))
						throw "Neko typed program contains duplicate function " + declaration;
					functions.set(declaration, {owner: owner, body: body});
				}
			}
		}
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
		return {owner: selected.owner, body: selected.body};
	}
}
