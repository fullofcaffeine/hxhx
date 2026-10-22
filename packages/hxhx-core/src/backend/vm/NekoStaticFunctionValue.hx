package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/**
 * Select a static function value from its checked source occurrence.
 * Type qualifiers do not require runtime class objects. The selected declaration
 * distinguishes a stable function symbol from dynamic-method storage; ordinary
 * callable fields keep their own field plans. Reads and writes use one owner.
 */
function fromExpression(context:NekoEmitContext, expression:HxExpr):Null<NekoProjectedFunction> {
	if (context == null || context.currentExecutable == null)
		return null;
	switch expression {
		case EIdent(name) if (context.locals == null || !context.locals.exists(name)):
		case EField(_, _):
		case _:
			return null;
	}
	final source = switch context.currentExecutable {
		case FunctionBody(selected):
			final current = context.typedProgram.requireDeclaredFunction(selected.body.getDeclaration());
			if (current.body != selected.body || current.owner != selected.owner)
				throw "Neko static function value belongs to another function projection";
			selected.body.findCallableExpression(expression);
		case FieldInitializer(selected):
			if (context.typedProgram.requireDeclaredInitializer(selected.getDeclaration()) != selected)
				throw "Neko static function value belongs to another initializer projection";
			selected.findCallableExpression(expression);
	};
	final declaration = source == null ? null : source.getDeclaration();
	if (declaration == null || !declaration.getIsStatic() || declaration.getIsEnumConstructor())
		return null;
	switch source.getTag() {
		case NameRead:
		case FieldRead if (source.getExpressions().length == 1 && source.getExpressions()[0].getTag() == RuntimeTypeValue):
		case _:
			return null;
	}
	declaration.requireSupportedImplementation();
	return context.typedProgram.requireFunction(declaration.getOwner().getCanonicalName(), declaration.getIdentity().getCanonicalKey());
}
