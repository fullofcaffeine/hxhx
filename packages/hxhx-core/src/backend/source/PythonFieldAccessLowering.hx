package backend.source;

import haxe.ds.ObjectMap;
import haxe.ds.StringMap;

/**
	Keep Python field accesses attached to the declaration selected by typing.

	Bare field names and local variables can share a source spelling. The exact
	function catalogs distinguish them before Python decides whether an assignment
	is local. Static fields become class attributes; instance fields use self.
	Module-qualified constructor types use their emitted class declaration name.
	Runtime type operands (`Std.isOfType`, `is`, class values) are resolved
	through the same exact projection and lowered by `PythonRuntimeTypeLowering`.
	The maps belong to one emission and never survive a compiler request.
**/
class PythonFieldAccessLowering {
	final modules:ObjectMap<HxClassDecl, TypedModule> = new ObjectMap();
	final ownerNames:StringMap<String> = new StringMap();
	final moduleNames:StringMap<Bool> = new StringMap();
	final runtimeTypes:PythonRuntimeTypeLowering;
	var nextInitializer:Int = 0;

	public function new(program:MacroExpandedProgram) {
		final emittedClasses = new StringMap<HxClassDecl>();
		final emittedNames = new StringMap<String>();
		for (module in program.getTypedModules()) {
			// Python renders every emitted body from an exact projection below,
			// where each runtime type occurrence is lowered or rejected.
			for (declaration in HxModuleDecl.getClasses(module.getBackendStructureDeclaration())) {
				modules.set(declaration, module);
				moduleNames.set(HxClassDecl.getName(declaration), true);
			}
			// Python renders classes only from non-library modules; only those can answer a class test.
			final emitted = !SourceTargetCommon.isStdSourceFile(module.getParsed().getFilePath());
			for (typedClass in module.getTypedClasses()) {
				final info = typedClass.getSemanticInfo();
				if (info == null)
					continue;
				final canonical = info.getIdentity().getCanonicalName();
				final declaration = typedClass.getSourceDeclaration();
				final name = HxClassDecl.getName(declaration);
				ownerNames.set(canonical, name);
				if (!emitted || declaration.isExtern || declaration.enumDeclaration != null)
					continue;
				final previous = emittedNames.get(name);
				if (previous != null && previous != canonical) {
					// Python emits one class per short name, so neither identity is testable.
					emittedClasses.remove(previous);
					continue;
				}
				emittedNames.set(name, canonical);
				emittedClasses.set(canonical, declaration);
			}
		}
		runtimeTypes = new PythonRuntimeTypeLowering(emittedClasses);
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
		final runtimeFacts = functionFacts(projection);
		return SourceFunctionBodyRewriter.bodyWithOriginal(HxFunctionDecl.getBody(projection.getDeclaration()), function(original, expression) {
			final runtimeType = runtimeTypes.rewrite(runtimeFacts, original, expression);
			if (runtimeType != null)
				return runtimeType;
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

	/**
		Lower runtime type operands in one field initializer value or statement
		list taken from `projection`. Other field and constructor rewrites are not
		applied here; initializers keep their existing rendering path.
	**/
	public function initializerExpression(projection:TypedBackendFieldInitializerProjection, value:HxExpr):HxExpr {
		final facts = initializerFacts(projection);
		return SourceFunctionBodyRewriter.expressionWithOriginal(value, (original, expression) -> {
			final runtimeType = runtimeTypes.rewrite(facts, original, expression);
			runtimeType == null ? expression : runtimeType;
		});
	}

	public function initializerStatements(projection:TypedBackendFieldInitializerProjection, statements:Array<HxStmt>):Array<HxStmt> {
		final facts = initializerFacts(projection);
		return SourceFunctionBodyRewriter.bodyWithOriginal(statements, (original, expression) -> {
			final runtimeType = runtimeTypes.rewrite(facts, original, expression);
			runtimeType == null ? expression : runtimeType;
		});
	}

	static function functionFacts(projection:TypedBackendFunctionProjection):PythonRuntimeTypeLowering.PythonRuntimeTypeFacts
		return {requireRuntimeType: projection.requireRuntimeType, findCast: projection.findCast};

	static function initializerFacts(projection:TypedBackendFieldInitializerProjection):PythonRuntimeTypeLowering.PythonRuntimeTypeFacts
		return {requireRuntimeType: projection.requireRuntimeType, findCast: projection.findCast};
}
