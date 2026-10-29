package backend.vm;

/**
	Select static storage from the exact field occurrence retained by typing.
	A qualifier's spelling cannot select a class, and a shadowing local has no
	field occurrence. Reads and writes therefore share the same declared owner.
	This selection does not execute initializers or choose startup order.
**/
function fromExpression(context:NekoEmitContext, expression:HxExpr, writing:Bool = false):Null<TyFieldInfo> {
	if (context == null || context.currentExecutable == null)
		return null;
	switch expression {
		case EIdent(_) | EField(_, _):
		case _:
			return null;
	}
	final occurrence = switch context.currentExecutable {
		case FunctionBody(selected):
			final current = context.typedProgram.requireDeclaredFunction(selected.body.getDeclaration());
			if (current.body != selected.body || current.owner != selected.owner)
				throw "Neko static field access belongs to another function projection";
			selected.body.findField(expression);
		case FieldInitializer(selected):
			if (context.typedProgram.requireDeclaredInitializer(selected.getDeclaration()) != selected)
				throw "Neko static field access belongs to another initializer projection";
			selected.findField(expression);
	};
	if (occurrence == null || !occurrence.getField().getIsStatic())
		return null;
	final field = occurrence.getField();
	final owner = context.typedProgram.requireClass(field.getOwner().getCanonicalName());
	final declared = owner.requireSemanticFacts().requireField(field);
	if (declared == null
		|| !declared.isStatic
		|| declared.typeIdentity != occurrence.getType().getSemanticKey()
		|| declared.isFinal != field.getIsFinal()
		|| declared.propertyGet != field.getPropertyGet()
		|| declared.propertySet != field.getPropertySet())
		throw "Neko static field occurrence conflicts with its exact declaration: "
			+ field.getCanonicalKey()
			+ " declared="
			+ (declared == null ? "missing" : declared.typeIdentity)
			+ " selected="
			+ field.getType().getSemanticKey()
			+ " result="
			+ occurrence.getType().getSemanticKey();
	if (occurrence.getReceiver() == ValueReceiver)
		throw "Neko static field access requires an effect-free type qualifier";
	final access = writing ? field.getPropertySet() : field.getPropertyGet();
	if ((writing && field.getIsFinal()) || (access != "" && access != "default" && access != "null"))
		throw "Neko static property access requires explicit shared accessor lowering";
	return field;
}
