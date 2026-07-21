/**
	Short public name for the expression-level declaration record.

	The real definition shares the `HxExpr` module with its recursive initializer
	type so generated OCaml does not need two modules that depend on each other.
**/
typedef HxExprVarDecl = HxExpr.HxExprVariableDeclaration;
