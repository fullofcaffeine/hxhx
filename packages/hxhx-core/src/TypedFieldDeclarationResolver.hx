/** Resolve the exact field and imported-name projection rule for one parsed field read. **/
typedef TypedFieldDeclarationResolver = (expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> Null<TypedFieldResolution>;
