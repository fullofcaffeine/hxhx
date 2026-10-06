/**
	Select C# statement operands from resolved API declarations.

	An unsafe body executes within its caller, so Void and abrupt completion are
	legal here even though neither is an ordinary argument value. The declaration
	identity remains on the typed node. Aliases resolve to that same declaration;
	user methods with a matching short name retain ordinary call checking.
 */
function select(declaration:Null<TyDeclarationInfo>, isCs:Bool):Null<HxTargetScopeKind> {
	if (!isCs
		|| declaration == null
		|| !declaration.getIsStatic()
		|| !declaration.getIsInline()
		|| declaration.getOwner().getCanonicalName() != "cs.Lib"
		|| declaration.getModulePath() != "cs.Lib")
		return null;
	return switch declaration.getSignature().getName() {
		case "unsafe" if (declaration.getSignature().getArgs().length == 1
			&& declaration.getSignature().getReturnType().isVoid()): CsUnsafe;
		case _: null;
	};
}

/** Recheck the selected declaration and structural layout after typed rewrites. */
function kind(node:TypedExpr):HxTargetScopeKind {
	final result = select(node.getDeclaration(), true);
	if (node.getTag() != TargetScope
		|| result == null
		|| node.getExpressions().length != 1
		|| (!node.getType().isVoid() && !node.getType().isNoNormalCompletion()))
		throw "native syntax scope lost its exact declaration, body, or completion type";
	return result;
}
