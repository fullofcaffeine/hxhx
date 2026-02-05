/**
	Expression AST for the `hih-compiler` bring-up.

	Why:
	- Stage 2 only needed a module “summary”. Stage 3 typing needs structured
	  expressions so we can infer types and produce a typed AST.
	- We keep this intentionally small and grow it rung-by-rung.

	What:
	- Supports a minimal subset needed by acceptance fixtures:
	  - constants (`null`, booleans, strings, ints, floats)
	  - identifier references
	  - field access (`a.b`)
	  - calls (`f(x, y)` and `a.b()`)

	How:
	- This is *not* the upstream Haxe AST. It is a bootstrap representation
	  designed to keep the example runnable in CI while we expand coverage.
**/
enum HxExpr {
	ENull;
	EBool(value:Bool);
	EString(value:String);
	EInt(value:Int);
	EFloat(value:Float);

	EIdent(name:String);
	EField(obj:HxExpr, field:String);
	ECall(callee:HxExpr, args:Array<HxExpr>);

	/**
		Unary operator expression (Stage 3 expansion).

		Why
		- Real-world Haxe code (including upstream tests) uses unary operators in
		  both expressions and conditions (`!flag`, `-x`).
		- Even before we *type* these operators, parsing them prevents downstream
		  stages from mis-interpreting tokens as identifiers/calls.

		What
		- Represents a prefix unary operation like `!e` or `-e`.

		How
		- Operators are stored as raw strings for now (e.g. `"!"`, `"-"`).
		- Typing and lowering are future Stage 3/4 work; Stage 3 emitters may
		  deliberately collapse these to bring-up escape hatches.
	**/
	EUnop(op:String, expr:HxExpr);

	/**
		Binary operator expression (Stage 3 expansion).

		Why
		- Even minimal Haxe code frequently uses arithmetic and comparisons
		  (`a + b`, `x == 0`, `i < n`).
		- Gate 1 (upstream unit macro suite) contains control flow and comparisons
		  inside function bodies. Parsing these shapes is a prerequisite for a
		  real typer.

		What
		- Represents infix binary ops, including assignment (`=`).

		How
		- Operators are stored as raw strings for now (`"+"`, `"=="`, `"="`, ...).
		- The parser only supports a curated subset of operators at this stage.
	**/
	EBinop(op:String, left:HxExpr, right:HxExpr);

	/**
		Best-effort placeholder for expressions we don't parse yet.

		We prefer to keep the parser permissive during early bootstrapping, while
		still allowing downstream stages to detect “unknown” shapes explicitly.
	**/
	EUnsupported(raw:String);
}
