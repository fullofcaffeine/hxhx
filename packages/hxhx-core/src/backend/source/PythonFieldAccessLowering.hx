package backend.source;

import haxe.ds.ObjectMap;
import haxe.ds.StringMap;

/**
	Keep Python field accesses attached to the declaration selected by typing.

	Bare field names and local variables can share a source spelling. The exact
	function catalogs distinguish them before Python decides whether an assignment
	is local. Static fields become class attributes; instance fields use self.
	Module-qualified constructor types use their emitted class declaration name.
	The maps belong to one emission and never survive a compiler request.
**/
class PythonFieldAccessLowering {
	final modules:ObjectMap<HxClassDecl, TypedModule> = new ObjectMap();
	final ownerNames:StringMap<String> = new StringMap();
	final moduleNames:StringMap<Bool> = new StringMap();
	var nextInitializer:Int = 0;

	public function new(program:MacroExpandedProgram) {
		for (module in program.getTypedModules()) {
			for (declaration in HxModuleDecl.getClasses(module.getBackendDeclaration())) {
				modules.set(declaration, module);
				moduleNames.set(HxClassDecl.getName(declaration), true);
			}
			for (typedClass in module.getTypedClasses()) {
				final info = typedClass.getSemanticInfo();
				if (info != null)
					ownerNames.set(info.getIdentity().getCanonicalName(), HxClassDecl.getName(typedClass.getSourceDeclaration()));
			}
		}
	}

	/** Module-level initializer helpers must not replace an authored class name. */
	public function initializerName():String {
		var name:String;
		do {
			name = "_hx_static_initializer_" + nextInitializer++;
		} while (moduleNames.exists(name));
		moduleNames.set(name, true);
		return name;
	}

	/** Static initialization consumes the exact field view that supplied its expression. */
	public function initializer(owner:HxClassDecl, field:HxFieldDecl):TypedBackendFieldInitializerProjection {
		final module = modules.get(owner);
		final selected = module == null ? null : module.findBackendFieldInitializer(owner, field);
		if (selected == null)
			throw "Python initializer requires its exact class and field declaration";
		return selected;
	}

	/** Resolve an exact legacy declaration pair through its owning typed module. */
	public function projection(owner:HxClassDecl, declaration:HxFunctionDecl):TypedBackendFunctionProjection {
		final module = modules.get(owner);
		final selected = module == null ? null : module.findBackendFunctionProjection(owner, declaration);
		if (selected == null)
			throw "Python field lowering requires an exact typed function declaration";
		return selected.functionProjection;
	}

	/** Rewrite exact field and constructor occurrences while retaining local names and argument effects. */
	public function body(projection:TypedBackendFunctionProjection):Array<HxStmt> {
		final locals = projection.getLocalCatalog();
		final fields = projection.getFieldReadCatalog();
		final constructors = projection.getConstructorCatalog().getEntries();
		return SourceFunctionBodyRewriter.bodyWithOriginal(HxFunctionDecl.getBody(projection.getDeclaration()), function(original, expression) {
			return switch (expression) {
				case ENew(_, arguments):
					var owner:Null<String> = null;
					for (entry in constructors)
						if (entry.getExpression() == original) {
							final identity = projection.requireConstructor(original).getConstructedType().getNominalIdentity();
							owner = identity == null ? null : ownerNames.get(identity.getCanonicalName());
							break;
						}
					owner == null ? expression : ENew(owner, arguments);
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
