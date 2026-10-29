/** Resolve a value read using its lexical scope and actual enclosing expectation, before target projection. */
typedef TypedMemberDeclarationResolver = (expression:HxExpr, diagnosticPosition:HxPos, environment:TyFunctionEnv,
	expected:Null<TyType>) -> Null<TypedMemberResolution>;
