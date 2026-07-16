/** Resolves one source expression against the exact lexical scope being sealed. **/
typedef TypedExprTypeResolver = (expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> TyType;
