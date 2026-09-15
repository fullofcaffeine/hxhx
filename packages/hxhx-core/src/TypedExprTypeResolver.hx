/** Shared type and runtime-target queries bound to the exact lexical and declaration context. */
typedef TypedExprTypeResolver = {
	final expressionType:(expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv) -> TyType;
	final runtimeTypeTarget:(expression:HxExpr, environment:TyFunctionEnv, namespace:TypedRuntimeTypeNamespace) -> Null<TypedRuntimeTypeTarget>;
}
