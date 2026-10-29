/** Resolve the exact declaration with the same result context used to type the call. **/
typedef TypedCallDeclarationResolver = (callee:HxExpr, arguments:Array<HxExpr>, diagnosticPosition:HxPos, environment:TyFunctionEnv, callExpression:HxExpr,
	resultContext:Null<TyType>) -> TypedCallResolution;
