package backend.vm;

/**
	Complete a local callable's omitted optional arguments from its checked type.

	Shared projection preserves trailing omissions for targets that observe the
	argument count. Neko requires the fixed arity promised by a stored callable,
	even when a cast gave that value a different signature from its declaration.
	Only exact local binding facts authorize null padding. Rest adapters and
	explicit cast expressions retain their existing separate call contracts.
 */
function complete(context:NekoEmitContext, callee:HxExpr, arguments:Array<String>):Array<String> {
	final name = switch callee {
		case EIdent(name): name;
		case EParenthesized(inner, _): return complete(context, inner, arguments);
		case _: return arguments;
	};
	if (context.locals == null || !context.locals.exists(name))
		return arguments;
	final catalog = switch context.currentExecutable {
		case FunctionBody(fn): fn.body.getLocalCatalog();
		case FieldInitializer(initializer): initializer.getLocalCatalog();
		case null: throw "Neko local call requires its exact executable projection";
	};
	final local = catalog.findByProjectedName(name);
	if (local == null)
		throw "Neko local call is absent from its binding catalog";
	final type = TyAliasExpansion.revealNonNullable(local.getBinding().getType());
	if (!type.isFunction())
		return arguments;
	final parameters = type.getFunctionParameters();
	if (arguments.length >= parameters.length)
		return arguments;
	for (parameter in parameters)
		if (parameter.isRest)
			return arguments;
	for (index in arguments.length...parameters.length)
		if (!parameters[index].isOptional)
			return arguments;
	final completed = arguments.copy();
	while (completed.length < parameters.length)
		completed.push("null");
	return completed;
}
