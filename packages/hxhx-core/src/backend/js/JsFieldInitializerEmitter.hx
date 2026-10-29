package backend.js;

/** Emit a field's checked statements before its value, without adding a function or changing `this`. */
function emit(writer:JsWriter, owner:TypedBackendClassProjection, field:HxFieldDecl, parent:JsFunctionScope, types:JsRuntimeTypeScope):Null<String> {
	for (projection in owner.getFieldInitializers())
		if (projection.getDeclaration() == field) {
			projection.assertCurrent();
			final plan = TypedControlStatements.initializerBody(projection.getExpression(), projection.getStableIdentity(), null, projection.requireExpression);
			final scope = JsFunctionScope.initializer(parent, projection, types);
			final statements = new JsWriter();
			JsStmtEmitter.emitFunctionBody(statements, plan.statements, scope);
			final value = plan.value == null ? null : JsExprEmitter.emit(plan.value, scope.exprScope());
			// A rejected initializer must not leave partial effects in the output.
			final lines = statements.toString().split("\n");
			for (index in 0...lines.length - 1)
				writer.writeln(lines[index]);
			return value;
		}
	throw "JavaScript field initializer requires its exact executable projection";
}
