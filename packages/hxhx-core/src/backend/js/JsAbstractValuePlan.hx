package backend.js;

/**
	Keep abstract values erased to their backing values across JavaScript boundaries.
	Generated constructor and method helpers still use an internal receiver record.
	Only a declaration selected by the current typed program can use that helper ABI;
	ordinary objects, unchecked casts, and matching source spellings cannot select it.
 */
class JsAbstractValuePlan {
	final functions = new haxe.ds.ObjectMap<TypedBackendFunctionProjection, Bool>();
	final initializers = new haxe.ds.ObjectMap<TypedBackendFieldInitializerProjection, Bool>();
	final abstracts = new haxe.ds.StringMap<JsClassInheritancePlan.JsClassInheritanceNode>();
	final methods = new haxe.ds.ObjectMap<TyDeclarationInfo, TypedBackendFunctionProjection>();

	public function new(program:MacroExpandedProgram, inheritance:JsClassInheritancePlan) {
		inheritance.assertProgram(program);
		for (module in program.getTypedModules())
			for (owner in module.getBackendProjection().getClasses()) {
				final node = inheritance.requireClass(owner);
				if (node.abstractReceiver)
					abstracts.set(node.identity, node);
				for (fn in owner.getFunctions()) {
					functions.set(fn, true);
					if (node.abstractReceiver)
						methods.set(fn.requireSemanticDeclaration(), fn);
				}
				for (field in owner.getFieldInitializers())
					initializers.set(field, true);
			}
	}

	/** Ordinary declarations retain ordinary dispatch. Abstract helpers require exact declaration identity. */
	function methodReference(declaration:TyDeclarationInfo):Null<String> {
		final node = abstracts.get(declaration.getOwner().getCanonicalName());
		if (node == null)
			return null;
		final method = methods.get(declaration);
		if (method == null || method.requireSemanticDeclaration() != declaration || node.usesHostPath)
			throw "JavaScript abstract operation has no exact generated helper";
		method.requireCaptureCatalog();
		return node.reference;
	}

	/** Ordinary abstract construction uses its selected value factory; multi-type factories must already be lowered. */
	function constructorReference(occurrence:TypedBackendConstructorOccurrence):Null<String> {
		final identity = occurrence.getConstructedType().getNominalIdentity();
		if (identity == null || !abstracts.exists(identity.getCanonicalName()))
			return null;
		final application = occurrence.requireApplication();
		if (application.getMultiTypeConstruction() != null)
			throw "JavaScript multi-type construction requires its shared selected factory";
		if (application.getUnderlyingType() == null)
			return null;
		return methodReference(application.getDeclaration());
	}

	function scope(construct:HxExpr->TypedBackendConstructorOccurrence, call:HxExpr->Null<TypedBackendInstanceCallOccurrence>,
			requireExpression:HxExpr->Void):JsAbstractValueScope {
		return {
			// The decoded canonical owner only selects a candidate path. Exact
			// occurrence and declaration checks still authorize every helper call.
			isAbstractOwner: owner -> abstracts.exists(owner),
			constructorReference: expression -> {
				requireExpression(expression);
				return constructorReference(construct(expression));
			},
			requireCall: expression -> {
				final result = call(expression);
				if (result == null)
					throw "JavaScript instance call is not an exact executable occurrence";
				return result;
			},
			methodReference: methodReference
		};
	}

	public function forFunction(fn:TypedBackendFunctionProjection):JsAbstractValueScope {
		if (!functions.exists(fn))
			throw "JavaScript abstract scope has a foreign function projection";
		return scope(fn.requireConstructor, fn.findInstanceCall, fn.requireExpression);
	}

	public function forInitializer(field:TypedBackendFieldInitializerProjection):JsAbstractValueScope {
		if (!initializers.exists(field))
			throw "JavaScript abstract scope has a foreign field initializer";
		return scope(field.requireConstructor, field.findInstanceCall, field.requireExpression);
	}
}
