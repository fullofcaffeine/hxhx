/**
	Statement AST for the `hih-compiler` bring-up.

	Why:
	- The typer must distinguish statement vs expression positions (especially
	  around `return`).
	- Even if we only parse a few statement forms today, having an explicit
	  statement layer keeps later expansions predictable.

	What:
	- Minimal subset:
	  - `return <expr>;`
	  - expression statements (for call-only bodies)

	How:
	- Additional statement forms (var declarations, if/while, blocks, etc.) will
	  be added as Stage 3 expands.
**/
enum HxStmt {
	SReturnVoid;
	SReturn(expr:HxExpr);
	SExpr(expr:HxExpr);
}
