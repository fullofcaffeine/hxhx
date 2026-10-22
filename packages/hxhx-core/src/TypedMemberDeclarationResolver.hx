/** Resolve a value read before backend projection loses its lexical import context. */
typedef TypedMemberDeclarationResolver = (expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> Null<TypedMemberResolution>;
