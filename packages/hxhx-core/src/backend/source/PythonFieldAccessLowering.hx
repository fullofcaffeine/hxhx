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
	through the same exact projection and lowered by `PythonRuntimeTypeLowering`;
	static calls Python cannot execute are rejected by `PythonStaticCallAdmission`.
	The maps belong to one emission and never survive a compiler request.
**/
class PythonFieldAccessLowering {
	final modules:ObjectMap<HxClassDecl, TypedModule> = new ObjectMap();
	final ownerNames:StringMap<String> = new StringMap();
	final moduleNames:StringMap<Bool> = new StringMap();
	final runtimeTypes:PythonRuntimeTypeLowering;
	final staticCalls:PythonStaticCallAdmission;
	var nextInitializer:Int = 0;

	public function new(program:MacroExpandedProgram) {
		final testableClasses = new StringMap<String>();
		final renderedOwners = new StringMap<Bool>();
		final emittedNames = new StringMap<String>();
		for (module in program.getTypedModules()) {
			// Python renders every emitted body from an exact projection, where
			// each runtime type occurrence is lowered or rejected.
			final declarations = HxModuleDecl.getClasses(module.getPythonStructureDeclaration());
			final typedClasses = module.getTypedClasses();
			if (declarations.length != typedClasses.length)
				throw "Python field lowering lost the typed class paired with a declaration";
			for (index in 0...declarations.length) {
				final declaration = declarations[index];
				modules.set(declaration, module);
				moduleNames.set(HxClassDecl.getName(declaration), true);
				final info = typedClasses[index].getSemanticInfo();
				if (info == null)
					continue;
				final canonical = info.getIdentity().getCanonicalName();
				ownerNames.set(canonical, HxClassDecl.getName(typedClasses[index].getSourceDeclaration()));
				// Emission and runtime class tests share one rule for which classes exist in Python.
				final pythonName = SourceTargetCommon.pythonEmittedClassName(module.getParsed().getFilePath(), declaration);
				if (pythonName == null)
					continue;
				renderedOwners.set(canonical, true);
				if (declaration.isExtern || declaration.enumDeclaration != null || declaration.isInterface)
					continue;
				final previous = emittedNames.get(pythonName);
				if (previous != null && previous != canonical) {
					// Python emits only the first class with a name, so neither identity is testable.
					testableClasses.remove(previous);
					continue;
				}
				emittedNames.set(pythonName, canonical);
				testableClasses.set(canonical, pythonName);
			}
		}
		runtimeTypes = new PythonRuntimeTypeLowering(testableClasses);
		staticCalls = new PythonStaticCallAdmission(renderedOwners);
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
			staticCalls.check(original);
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
		Lower runtime type operands and admit static calls in one field
		initializer value or statement list taken from `projection`. Other field and constructor rewrites are not
		applied here; initializers keep their existing rendering path.
	**/
	public function initializerExpression(projection:TypedBackendFieldInitializerProjection, value:HxExpr):HxExpr {
		final facts = initializerFacts(projection);
		return SourceFunctionBodyRewriter.expressionWithOriginal(value, (original, expression) -> {
			staticCalls.check(original);
			final runtimeType = runtimeTypes.rewrite(facts, original, expression);
			runtimeType == null ? expression : runtimeType;
		});
	}

	public function initializerStatements(projection:TypedBackendFieldInitializerProjection, statements:Array<HxStmt>):Array<HxStmt> {
		final facts = initializerFacts(projection);
		return SourceFunctionBodyRewriter.bodyWithOriginal(statements, (original, expression) -> {
			staticCalls.check(original);
			final runtimeType = runtimeTypes.rewrite(facts, original, expression);
			runtimeType == null ? expression : runtimeType;
		});
	}

	static function functionFacts(projection:TypedBackendFunctionProjection):PythonRuntimeTypeLowering.PythonRuntimeTypeFacts
		return {requireRuntimeType: projection.requireRuntimeType, findCast: projection.findCast};

	static function initializerFacts(projection:TypedBackendFieldInitializerProjection):PythonRuntimeTypeLowering.PythonRuntimeTypeFacts
		return {requireRuntimeType: projection.requireRuntimeType, findCast: projection.findCast};
}
