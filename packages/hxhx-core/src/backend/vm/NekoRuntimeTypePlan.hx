package backend.vm;

/** Select a runtime type operand only from the current program's exact executable projection. */
function fromExpression(context:NekoEmitContext, expression:HxExpr):Null<TypedBackendRuntimeTypeOccurrence> {
	if (!TypedRuntimeTypeSource.isMarker(expression))
		return null;
	if (context == null || context.typedProgram == null || context.currentExecutable == null)
		throw "Neko runtime type operand requires an executable projection";
	return switch (context.currentExecutable) {
		case FunctionBody(selected):
			final current = context.typedProgram.requireDeclaredFunction(selected.body.getDeclaration());
			if (current.body != selected.body || current.owner != selected.owner)
				throw "Neko runtime type operand has a foreign function projection";
			current.body.requireRuntimeType(expression);
		case FieldInitializer(selected):
			final current = context.typedProgram.requireDeclaredInitializer(selected.getDeclaration());
			if (current != selected)
				throw "Neko runtime type operand has a foreign initializer projection";
			current.requireRuntimeType(expression);
	};
}
