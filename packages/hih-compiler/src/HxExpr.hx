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

	/**
		`this` expression.

		Why
		- Instance field access and method calls (`this.x`, `this.f()`) are core
		  Haxe semantics and appear early in upstream fixtures.
	**/
	EThis;

	/**
		`super` expression.

		Why
		- Upstream Haxe code uses `super()` in constructors and `super.method()`
		  in overrides. Stage 3 parsing must not mis-tokenize this as an
		  identifier.

		Note
		- Typing/semantics for `super` require class hierarchy information and is
		  deferred; for now, we treat it as a distinct expression node.
	**/
	ESuper;

	EIdent(name:String);
	EField(obj:HxExpr, field:String);
	ECall(callee:HxExpr, args:Array<HxExpr>);

	/**
		Arrow-function / lambda expression (Stage 3 expansion): `arg -> expr`.

		Why
		- Upstream Haxe code (and tests) frequently uses the Haxe 4 “short function”
		  syntax as a lightweight callback, e.g.:
		  - `arr.iter(x -> trace(x))`
		  - `xs.map(x -> x + 1)`
		- Without parsing this shape, our bootstrap parser drifts at the `->` token
		  and produces `EUnsupported` placeholders in otherwise straight-line code.

		What
		- Stores the argument names (bring-up: currently only simple identifiers).
		- Stores the body expression.

		How (bring-up semantics)
		- Stage 3 typer treats the resulting value as `Dynamic`, but still types the
		  body with a nested scope that:
		  - introduces the lambda argument(s),
		  - and keeps outer locals/params visible for capture.
		- Stage 3 emitter lowers this to an OCaml `fun ... -> ...` closure.
	**/
	ELambda(args:Array<String>, body:HxExpr);

	/**
		Constructor call: `new TypePath(args...)`.

		Why
		- Gate 1 fixtures and real programs allocate objects and then access
		  fields/methods. A Stage 3 typer cannot type instance field access
		  without being able to type object construction.

		What
		- Stores a raw dotted type path (e.g. `demo.Point`).
		- Stores the argument expressions.
	**/
	ENew(typePath:String, args:Array<HxExpr>);

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
		Ternary conditional expression: `cond ? thenExpr : elseExpr`.

		Why
		- Common in upstream code and libraries (including unit-test frameworks).
		- Parsing it prevents the "expression parser stops at '?'" drift that can cascade into
		  statement-level parse failures.

		What
		- Stores:
		  - condition expression
		  - then/else branch expressions

		How
		- Stage 3 typer performs best-effort unification of branch types.
		- Stage 3 emitters may lower it directly to an OCaml `if ... then ... else ...`.
	**/
	ETernary(cond:HxExpr, thenExpr:HxExpr, elseExpr:HxExpr);

	/**
		Anonymous-structure literal: `{ field: expr, ... }`.

		Why
		- Anonymous structures are pervasive in real Haxe code (status objects, options, etc.).
		- If we don't parse them, balanced braces inside expressions can accidentally terminate
		  function-body parsing early.

		What
		- Stores a stable ordered field list.

		How
		- Stage 3 typer currently treats the resulting value as `Dynamic`, but still types each
		  field initializer for basic checking/local inference.
	**/
		EAnon(fieldNames:Array<String>, fieldValues:Array<HxExpr>);

		/**
			Array literal: `[e1, e2, ...]`.

			Why
			- Core Haxe code and common libraries use `[]` frequently (temporary arrays, buffers, etc.).
			- Stage3 needs to parse this shape to avoid generating `EUnsupported("[")` in std code (e.g. `Bytes.toHex`).

			How
			- We keep this representation minimal: just the ordered element list.
			- Stage3 typer treats this as `Array<Dynamic>` for now.
		**/
		EArrayDecl(values:Array<HxExpr>);

		/**
			Array access: `arr[index]`.

			Why
			- Indexing is used pervasively in stdlib code (`b[i]`, `chars[c >> 4]`).
			- Even before we model the full `ArrayAccess` semantics, parsing avoids
			  token drift and enables a real typer later.
		**/
		EArrayAccess(array:HxExpr, index:HxExpr);

		/**
			Cast expression: `cast expr` or `cast(expr, Type)`.

			Why
			- Gate1 inputs (e.g. utest) use `cast` to coerce `Dynamic` to concrete types.
			- Treating `cast` as unsupported makes upstream-shaped code look "unparseable",
			  even though the semantics are intentionally permissive.

			What
			- Stores the expression being cast.
			- Stores the optional raw type-hint text (when present).

			How
			- Stage3 typer:
			  - if a type hint is provided, trusts it as the resulting type (best-effort),
			  - otherwise, returns the inferred type of the inner expression.
		**/
		ECast(expr:HxExpr, typeHint:String);

		/**
			`untyped` escape hatch: `untyped expr`.

			Why
			- Upstream std code uses `untyped` to access target-specific primitives.
			- Stage3 bring-up should preserve the shape (so later stages can decide how
			  to lower it) without failing parsing/typing.

			How
			- Stage3 typer returns `Dynamic` (after typing the inner expression for locals).
		**/
		EUntyped(expr:HxExpr);

		/**
			Best-effort placeholder for expressions we don't parse yet.

			We prefer to keep the parser permissive during early bootstrapping, while
		still allowing downstream stages to detect “unknown” shapes explicitly.
	**/
	EUnsupported(raw:String);
}
