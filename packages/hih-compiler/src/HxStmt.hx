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
	/**
		Statement block: `{ <stmt>* }`.

		Why
		- Upstream-shaped Haxe code uses blocks everywhere (function bodies, if/else branches).
		- Without blocks, Stage 3 parsing can only “skim” bodies for `return`, which prevents
		  a real typer from building scopes later.

		What
		- Contains an ordered list of statements.

		How
		- This is a bootstrap representation; later rungs add positions and more statement forms.
	**/
	SBlock(stmts:Array<HxStmt>);

	/**
		Variable declaration: `var name[:Type] [= expr];`

		Why
		- Stage 3’s real typer needs locals to exist in the AST so it can build scopes.
		- Many upstream tests rely on locals even in simple helper functions.

		What
		- Stores the variable name.
		- Stores the optional type hint as raw text.
		- Stores the optional initializer expression.
	**/
	SVar(name:String, typeHint:String, init:Null<HxExpr>);

	/**
		If/else statement: `if (cond) thenStmt [else elseStmt]`.

		Why
		- Control flow is pervasive in upstream code and is necessary for Gate 1.
		- Even before typing control flow correctly, parsing it avoids token drift and
		  makes later typing work local and structured.
	**/
	SIf(cond:HxExpr, thenBranch:HxStmt, elseBranch:Null<HxStmt>);

	SReturnVoid;
	SReturn(expr:HxExpr);
	SExpr(expr:HxExpr);
}
