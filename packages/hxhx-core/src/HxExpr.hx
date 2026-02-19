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
		Bare enum-like value reference (Stage 3 bring-up).

		Why
		- Upstream test harnesses often use unqualified “enum-ish” values like `Macro`,
		  `GithubActions`, etc. In real Haxe these might be enum constructors or
		  `enum abstract` values.
		- In early bring-up, emitting a bare uppercase identifier as an OCaml constructor
		  produces “unbound constructor” errors unless we model the full type.

		What
		- Represents a bare uppercase identifier used as a *value* (not a module/type prefix).

		How (bring-up semantics)
		- Stage3 typer treats this as `String`.
		- Stage3 bootstrap emitter lowers it to a stable string tag (e.g. `"Macro"`), which is
		  sufficient for simple switch/case dispatch in harness code.
	**/
	EEnumValue(name:String);

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
		Try/catch expression (Stage 3 expansion): `try { ... } catch(e:Dynamic) { ... }`.

		Why
		- Upstream Haxe code and tests often use `try` as an *expression* (not only as a statement),
		  typically to parse/validate something and fall back to a default value.
		- Gate2 diagnostics currently hit this in the upstream sourcemaps fixture where a `try` is
		  used as a variable initializer.

		What
		- Stores a canonical, token-rendered string of the entire expression.

		Why store raw text (bootstrap constraint)
		- A fully-structured try/catch expression would naturally contain statement lists
		  (`HxStmt`), but `HxStmt` already references `HxExpr`. Making `HxExpr` reference
		  `HxStmt` creates an OCaml module dependency cycle in the Stage3 bootstrap output.

		How (bring-up semantics)
		- Stage 3 typer treats this expression as `Dynamic`.
		- Stage 3 emitter lowers it to a conservative placeholder (`Obj.magic`) for now.
		- Correct semantics (exception mapping + block-expression values) are Stage 4+ work.
	**/
	ETryCatchRaw(raw:String);

	/**
		Switch expression (Stage 3 expansion): `switch (expr) { case ...: ... }`.

		Why
		- Upstream Haxe code (including the runci harness) uses `switch` as an *expression*,
		  e.g.:
		  - `var tests:Array<TestTarget> = switch (...) { ... }`
		- If we treat `switch` as a single-token `EUnsupported("switch")`, we risk leaving the
		  `{ ... }` body unconsumed, which can prematurely terminate function-body parsing and
		  cascade into many unrelated `unsupported_exprs_total` diagnostics.

		What
		- Stores a canonical, token-rendered string of the entire switch expression.

		Why store raw text (bootstrap constraint)
		- A structured switch naturally contains statements/blocks (and might contain `return`,
		  nested `switch`, etc.). Modeling that precisely would expand the bootstrap AST and
		  requires more of the typer/emitter than we want for Gate bring-up.
		- Like `ETryCatchRaw`, this avoids an OCaml bootstrap module-cycle hazard while still
		  letting the parser *consume* the whole switch expression deterministically.

		How (bring-up semantics)
		- Stage 3 typer treats this expression as `Dynamic`.
		- Stage 3 emitter lowers it to a conservative placeholder (`Obj.magic`).
		- Correct semantics (pattern matching + guards + expression values) are Stage 4+ work.
	**/
	ESwitchRaw(raw:String);

	/**
		Switch expression with a minimal, structured case list (Stage 3 bring-up).

		Why
		- `ESwitchRaw` lets the parser consume braces deterministically, but it prevents
		  running orchestration code under the Stage3 bootstrap emitter.
		- Gate2’s stage3 emit-runner needs `switch` to work for the upstream RunCi harness
		  (selecting targets and controlling subprocess execution).

		What
		- A scrutinee expression and an ordered list of cases.
		- Each case stores:
		  - a small pattern (`HxSwitchPattern`)
		  - a single expression result

		How (bootstrap constraints)
		- Case bodies are expressions (not statement blocks) so we avoid introducing an
		  OCaml bootstrap module cycle (`HxStmt` already references `HxExpr`).
		- Full Haxe switch semantics are deferred; see `HxSwitchPattern` docs for the
		  supported subset.
	**/
	ESwitch(scrutinee:HxExpr, cases:Array<{ pattern:HxSwitchPattern, expr:HxExpr }>);

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
			Array comprehension expression: `[for (name in iterable) expr]`.

			Why
			- Upstream `tests/RunCi.hx` uses this to derive a target list from an env-var string:
			  `[for (v in env.split(",")) v.trim().toLowerCase()]`.
			- In early bring-up, treating this as `EUnsupported` makes the resulting array contain
			  `(Obj.magic 0)` elements, which breaks `switch (test)` dispatch and prevents Gate2
			  from exercising real `runCommand("haxe", ...)` sub-invocations.

			What
			- Stores:
			  - the loop variable name
			  - the iterable expression
			  - the yielded element expression

			How (bring-up semantics)
			- Stage 3 typer models this as `Array<Dynamic>` and types the body in a nested scope
			  that binds `name` as `Dynamic` (or `Array<T>` element type when inferable).
			- Stage 3 emitter lowers this to:
			  - allocate an empty array
			  - iterate the iterable
			  - push each yielded element
			  - return the filled array
		**/
		EArrayComprehension(name:String, iterable:HxExpr, yieldExpr:HxExpr);

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
			Range expression: `start...end`.

			Why
			- This shape appears most often in `for` loops (`for (i in 0...n)`), which are used
			  heavily by upstream compiler test harnesses (including Gate2 bring-up).

			What
			- Stores the start and end expressions (end is **exclusive**, like Haxe).

			How (bring-up)
			- Today this node is only produced by the Stage3 parser for `for (i in start...end)`
			  loops so the Stage3 bootstrap emitter can lower it to an OCaml `for` loop without
			  needing a full `IntIterator` runtime model.
		**/
		ERange(start:HxExpr, end:HxExpr);

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
