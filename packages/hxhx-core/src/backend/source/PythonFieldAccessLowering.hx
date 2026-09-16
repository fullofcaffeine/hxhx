package backend.source;

import haxe.ds.ObjectMap;
import haxe.ds.StringMap;

/**
	Keep Python field accesses attached to the declaration selected by typing.

	Bare field names and local variables can share a source spelling. The exact
	function catalogs distinguish them before Python decides whether an assignment
	is local. Static fields become class attributes; instance fields use self.
	The maps belong to one emission and never survive a compiler request.
**/
class PythonFieldAccessLowering {
	final modules:ObjectMap<HxClassDecl, TypedModule> = new ObjectMap();
	final ownerNames:StringMap<String> = new StringMap();

	public function new(program:MacroExpandedProgram) {
		for (module in program.getTypedModules()) {
			for (declaration in HxModuleDecl.getClasses(module.getBackendDeclaration()))
				modules.set(declaration, module);
			for (typedClass in module.getTypedClasses()) {
				final info = typedClass.getSemanticInfo();
				if (info != null)
					ownerNames.set(info.getIdentity().getCanonicalName(), HxClassDecl.getName(typedClass.getSourceDeclaration()));
			}
		}
	}

	/** Resolve an exact legacy declaration pair through its owning typed module. */
	public function projection(owner:HxClassDecl, declaration:HxFunctionDecl):TypedBackendFunctionProjection {
		final module = modules.get(owner);
		final selected = module == null ? null : module.findBackendFunctionProjection(owner, declaration);
		if (selected == null)
			throw "Python field lowering requires an exact typed function declaration";
		return selected.functionProjection;
	}

	/** Rewrite only catalogued field accesses; projected locals remain local even when their original names match. */
	public function body(projection:TypedBackendFunctionProjection):Array<HxStmt> {
		final locals = projection.getLocalCatalog();
		final fields = projection.getFieldReadCatalog();
		return SourceFunctionBodyRewriter.body(HxFunctionDecl.getBody(projection.getDeclaration()), function(expression) {
			return switch (expression) {
				case EIdent(name):
					final entry = locals.findByProjectedName(name) == null ? fields.findByProjectedName(name) : null;
					if (entry == null) {
						expression;
					} else {
						final field = entry.getField();
						if (!field.getIsStatic()) {
							EField(EThis, field.getName());
						} else {
							final owner = ownerNames.get(field.getOwner().getCanonicalName());
							if (owner == null)
								throw "Python static field has no emitted declaration owner: " + field.getCanonicalKey();
							EField(EIdent(owner), field.getName());
						}
					}
				case _:
					expression;
			};
		});
	}
}
