package hxhx;

import hxhx.ExprMacroDeclarationSelector.ExprMacroSelectionScope;

/** One source-call decision, made before any receiver or argument is visited. */
enum ExprMacroCallRewrite {
	/** Consume the original syntax. Its children are not traversed. */
	Consume(replacement:HxExpr);

	/** Visit receiver and arguments in order, then transform the rebuilt call once. */
	Recurse(afterChildren:HxExpr->HxExpr);
}

/** Callers prepare semantic context themselves when selecting declarations; traversal supplies syntax ownership only. */
typedef ExprMacroCallRewriter = (call:HxExpr, context:ExprMacroSourceContext, scope:ExprMacroSelectionScope) -> ExprMacroCallRewrite;
