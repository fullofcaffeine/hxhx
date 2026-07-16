/** Resolves the exact shared declaration selected for a call in its lexical scope. **/
typedef TypedCallDeclarationResolver = (callee:HxExpr, arguments:Array<HxExpr>, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> Null<TyDeclarationInfo>;
