package backend.vm;

/** Install function-valued definitions once, then execute startup methods and ordered field effects. */
@:access(backend.vm.NekoTargetCore)
class NekoStaticInitializationEmitter {
	public static function render(out:Array<String>, context:NekoEmitContext, plan:NekoStaticInitializationPlan):Void {
		final classes = plan.getClasses();
		for (owner in classes) {
			final info = NekoTargetCore.exactClassInfo(context, owner);
			final local = NekoTargetCore.withCurrentClass(context, info);
			for (initializer in owner.getFieldInitializers()) {
				if (plan.isEarlyFunction(initializer))
					renderInitializer(out, local, initializer);
				final native = plan.earlyNativeBinding(initializer);
				if (native != null) {
					final field = initializer.getField();
					out.push(NekoTargetCore.renderStaticObjectRef(field.getOwner().getCanonicalName())
						+ "."
						+ NekoTargetCore.safeIdent(field.getName())
						+ " = $loader.loadprim("
						+ NekoTargetCore.quote(native.library + "@" + native.primitive)
						+ ", "
						+ native.arity
						+ ");");
				}
			}
		}
		for (owner in classes) {
			final info = NekoTargetCore.exactClassInfo(context, owner);
			for (fn in owner.getFunctions()) {
				final declaration = fn.requireSemanticDeclaration();
				if (declaration.getSignature().getName() == "__init__")
					out.push(NekoTargetCore.renderFunctionRef(context, info.fullName, "__init__") + "();");
			}
		}
		for (owner in classes) {
			final info = NekoTargetCore.exactClassInfo(context, owner);
			final classContext = NekoTargetCore.withCurrentClass(context, info);
			for (initializer in owner.getFieldInitializers()) {
				final field = initializer.getField();
				if (!field.getIsStatic() || plan.isEarlyFunction(initializer))
					continue;
				renderInitializer(out, classContext, initializer);
			}
		}
	}

	/** Both phases retain the exact initializer catalogs and the same value/statement rendering. */
	static function renderInitializer(out:Array<String>, context:NekoEmitContext, initializer:TypedBackendFieldInitializerProjection):Void {
		initializer.assertCurrent();
		final field = initializer.getField();
		final local = NekoTargetCore.withFieldInitializer(context, initializer.getDeclaration());
		final body = NekoControlStatements.initializerBody(initializer.getExpression(), initializer.getStableIdentity(), local);
		for (statement in body.statements)
			NekoTargetCore.renderStmt(out, local, statement, "");
		if (body.value != null)
			out.push(NekoTargetCore.renderStaticObjectRef(field.getOwner().getCanonicalName())
				+ "."
				+ NekoTargetCore.safeIdent(field.getName())
				+ " = "
				+ NekoEnumRuntimeType.tagValue(local, NekoTargetCore.renderExpr(local, body.value))
				+ ";");
	}
}
