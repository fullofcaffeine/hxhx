package backend.js;

/**
	Admit runtime type operands before output and bind them to their executable owner.
	A renderer cannot resolve a copied marker, another function's occurrence, or a
	class selected by its display name. Core representations remain explicit errors
	until their JavaScript behavior has its own acceptance evidence.
 */
class JsRuntimeTypePlan {
	final inheritance:JsClassInheritancePlan;
	final functions = new haxe.ds.ObjectMap<TypedBackendFunctionProjection, Bool>();
	final initializers = new haxe.ds.ObjectMap<HxFieldDecl, TypedBackendFieldInitializerProjection>();

	public function new(program:MacroExpandedProgram, inheritance:JsClassInheritancePlan) {
		program.assertTypedBodyRevisionsCurrent();
		inheritance.assertProgram(program);
		this.inheritance = inheritance;
		for (module in program.getTypedModules())
			for (owner in module.getBackendProjection().getClasses()) {
				for (fn in owner.getFunctions()) {
					functions.set(fn, true);
					fn.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inStatements(fn.getBody()));
					for (entry in fn.getRuntimeTypeCatalog().getEntries())
						reference(fn.requireRuntimeType(entry.getExpression()).getTarget());
				}
				for (field in owner.getFieldInitializers()) {
					initializers.set(field.getDeclaration(), field);
					field.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inExpression(field.getExpression()));
					for (entry in field.getRuntimeTypeCatalog().getEntries())
						reference(field.requireRuntimeType(entry.getExpression()).getTarget());
				}
			}
	}

	public function reference(target:TypedRuntimeTypeTarget):String {
		return switch (target.getKind()) {
			case Nominal(identity): inheritance.requireRuntimeClass(identity.getCanonicalName()).reference;
			case _: throw "JavaScript core runtime type operand is unsupported: " + target.getSemanticKey();
		};
	}

	public function forFunction(fn:TypedBackendFunctionProjection):JsRuntimeTypeScope {
		if (!functions.exists(fn))
			throw "JavaScript runtime type scope has a foreign function projection";
		return {requireOccurrence: fn.requireRuntimeType, reference: reference};
	}

	public function forInitializer(declaration:HxFieldDecl):JsRuntimeTypeScope {
		final field = initializers.get(declaration);
		if (field == null)
			throw "JavaScript runtime type scope has a foreign field initializer";
		return {requireOccurrence: field.requireRuntimeType, reference: reference};
	}
}
