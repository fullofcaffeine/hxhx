/** Resolve the exact declared field selected for one parsed field-read expression. **/
typedef TypedFieldDeclarationResolver = (expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> Null<TyFieldInfo>;
