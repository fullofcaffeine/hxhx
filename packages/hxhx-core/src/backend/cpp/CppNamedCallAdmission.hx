package backend.cpp;

/**
	Check named Int/Bool inputs before positional projection inserts null for skipped slots.

	Upstream C++ rejects a literal null passed to a bare scalar parameter, even when
	it has a default. Question-mark parameters and nullable variables remain valid.
	Shared alignment over the original typed operands distinguishes supplied null
	from omission. Projected null placeholders cannot prove that distinction.
	Numeric Float policy remains separate.
**/
function module(typed:TypedModule):Void {
	for (cls in typed.getTypedClasses()) {
		for (fn in cls.getFunctions()) {
			for (value in fn.getDefaults())
				expression(value.getExpression());
			for (value in fn.getBody().getStatements())
				statement(value);
		}
		for (initializer in cls.getFieldInitializers())
			expression(initializer.getExpression());
	}
}

private function statement(value:TypedStmt):Void {
	for (child in value.getExpressions())
		expression(child);
	for (child in value.getStatements())
		statement(child);
}

private function expression(value:TypedExpr):Void {
	if (value.getTag() == MacroExpr || value.getTag() == MacroType)
		return;
	if (value.getTag() == Call) {
		final declaration = value.getDeclaration();
		if (declaration != null && value.getExtensionProvider() == null && declaration.getSourceDeclaration() != null) {
			final written = HxFunctionDecl.getArgs(declaration.getSourceDeclaration());
			final signature = TyCallableSignature.fromDeclaration(declaration);
			final parameters = signature.getParameters();
			final arguments = value.getExpressions().slice(1);
			final operands = [for (argument in arguments) argument.getType()];
			// Only diagnose literal-null scalar inputs here. Other compatibility and
			// representation failures remain with their existing call owners.
			final slots = switch TyCallValidation.validate(signature, operands, [for (_ in arguments) TyCallAlignment.TyCallOperandKind.Value], Unchecked) {
				case Aligned(selected): selected;
				case Rejected(_): [];
			};
			if (written.length != parameters.length)
				throw "managed named call requires its exact parameter binding";
			for (index in 0...slots.length)
				switch slots[index] {
					case Supplied(source):
						final type = parameters[index].type.getSemanticKey();
						if (operands[source].isNullLiteral()
							&& !HxFunctionArg.getIsOptional(written[index])
							&& (type == "primitive:Int" || type == "primitive:Bool"))
							throw "managed named call literal null requires a nullable or question-mark parameter";
					case _:
				}
		}
	}
	for (child in value.getExpressions())
		expression(child);
}
