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
	SBlock(stmts:Array<HxStmt>, pos:HxPos);

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
	SVar(name:String, typeHint:String, init:Null<HxExpr>, pos:HxPos);

	/**
		If/else statement: `if (cond) thenStmt [else elseStmt]`.

		Why
		- Control flow is pervasive in upstream code and is necessary for Gate 1.
		- Even before typing control flow correctly, parsing it avoids token drift and
		  makes later typing work local and structured.
	**/
	SIf(cond:HxExpr, thenBranch:HxStmt, elseBranch:Null<HxStmt>, pos:HxPos);

	/**
		For-in loop: `for (name in iterable) body`.

		Why
		- Gate2 (and many upstream-ish workloads) use `for (i in 0...n)` and `for (x in arr)`
		  heavily for orchestration and simple iteration.
		- Even a minimal loop form unlocks a lot of "compiler-shaped" code paths (building lists
		  of work items, walking arrays, etc.).

		What
		- Stores:
		  - the loop variable name
		  - the iterable expression (bring-up supports `start...end` ranges and arrays)
		  - the loop body statement

		How (bring-up semantics)
		- Stage3 typer:
		  - declares the loop variable as a local (best-effort type: `Int` for `start...end`, otherwise `Dynamic`)
		  - types the body with that local in scope
		- Stage3 bootstrap emitter:
		  - lowers `start...end` to an OCaml `for` loop (exclusive end)
		  - lowers array iteration to `HxBootArray.iter`.
	**/
	SForIn(name:String, iterable:HxExpr, body:HxStmt, pos:HxPos);

	/**
		While loop: `while (cond) body`.

		Why
		- Core language parity requires statement-level while loops.
		- js-native coverage (and many real projects) uses `while` for index-style loops.

		What
		- Stores the loop condition expression and loop body statement.

		How (bring-up semantics)
		- The typer checks `cond` and types `body` in function scope.
		- Backend emitters lower this to native loop constructs for supported targets.
	**/
	SWhile(cond:HxExpr, body:HxStmt, pos:HxPos);

	/**
		Do/while loop: `do body while (cond);`.

		Why
		- This is part of core Haxe loop syntax and appears in real-world code.
		- js-native parity needs explicit support rather than collapsing to unsupported markers.

		What
		- Stores the loop body statement and loop condition expression.

		How (bring-up semantics)
		- Backend emitters preserve "run body at least once" behavior.
	**/
	SDoWhile(body:HxStmt, cond:HxExpr, pos:HxPos);

	/**
		Switch statement (Stage 3 bring-up).

		Why
		- The upstream `tests/RunCi.hx` harness uses statement-level `switch` to:
		  - handle platform differences (`switch (systemName)`), and
		  - dispatch to a target runner (`switch (test)`).
		- Without a structured switch statement, the Stage3 bootstrap emitter either:
		  - emits it as `Obj.magic` (no control flow), or
		  - truncates parsing due to unconsumed braces.

		What
		- A scrutinee expression and an ordered list of cases.
		- Each case stores:
		  - a small pattern (`HxSwitchPattern`)
		  - a statement body (typically a block)

		How (bring-up semantics)
		- This uses a restricted pattern subset (see `HxSwitchPattern`).
		- Lowered by the bootstrap emitter to nested `if ... then ... else ...` chains.
	**/
	SSwitch(scrutinee:HxExpr, cases:Array<{pattern:HxSwitchPattern, body:HxStmt}>, pos:HxPos);

	/**
		Try/catch statement: `try stmt catch(name[:Type]) stmt ...`.

		Why
		- Upstream-shaped orchestration code relies on exception flow for control-plane
		  behavior (command wrappers, cleanup paths, retry handoffs).
		- js-native needs a structured statement form so emitted JS can preserve runtime
		  control flow instead of failing with unsupported markers.

		What
		- Stores the try body and an ordered catch list.
		- Each catch stores:
		  - catch variable name,
		  - optional type hint text (kept for parity tracking),
		  - catch body statement.

		How (bring-up semantics)
		- Typing currently treats catch variables as `Dynamic`.
		- Non-js Stage3 emitters may still use permissive lowering while bring-up evolves.
	**/
	STry(tryBody:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>, pos:HxPos);

	/**
		Loop control statement: `break;`.

		Why
		- `break` is core statement-level control flow and should not be modeled as an
		  unsupported expression marker.
	**/
	SBreak(pos:HxPos);

	/**
		Loop control statement: `continue;`.

		Why
		- `continue` is core statement-level control flow and should not be modeled as an
		  unsupported expression marker.
	**/
	SContinue(pos:HxPos);

	/**
		Throw statement: `throw expr;`.

		Why
		- Needed to preserve exception control flow in statement-level try/catch handling.
	**/
	SThrow(expr:HxExpr, pos:HxPos);

	SReturnVoid(pos:HxPos);
	SReturn(expr:HxExpr, pos:HxPos);
	SExpr(expr:HxExpr, pos:HxPos);
}
