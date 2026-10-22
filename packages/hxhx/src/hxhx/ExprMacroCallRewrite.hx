package hxhx;

import hxhx.ExprMacroDeclarationSelector.ExprMacroSelectionScope;

/** One source-call decision, made before any receiver or argument is visited. */
enum ExprMacroCallRewrite {
	/** Consume the original syntax. Its children are not traversed. */
	Consume(replacement:HxExpr);

	/** Visit receiver and arguments in order, then transform the rebuilt call once. */
	Recurse(afterChildren:HxExpr->HxExpr);
}

/** A future dispatcher can consume a declaration-selected call without typing its syntax arguments. */
typedef ExprMacroCallRewriter = (call:HxExpr, context:TyperContext, scope:ExprMacroSelectionScope) -> ExprMacroCallRewrite;
