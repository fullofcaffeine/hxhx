/** Resolve the exact declaration and imported-name projection rule for one parsed call. **/
typedef TypedCallDeclarationResolver = (callee:HxExpr, arguments:Array<HxExpr>, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> TypedCallResolution;
