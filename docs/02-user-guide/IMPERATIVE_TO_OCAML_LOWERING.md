# Imperative → OCaml Lowering (How Haxe Becomes Idiomatic OCaml)

This doc explains how “imperative-looking” Haxe (mutation, loops, statement blocks) is lowered into OCaml
by `reflaxe.ocaml`, and how that differs between the two API surfaces:

- **Portable / stdlib-first surface (default)**: you write “normal Haxe”, using the Haxe stdlib, and the backend
  preserves Haxe semantics as much as possible while still emitting reasonable OCaml.
- **OCaml-native surface (opt-in)**: you choose target-native types/APIs (e.g. `ocaml.List`, `ocaml.Option`,
  `ocaml.Result`) and the backend emits direct OCaml idioms (`[]`, `(::)`, `Some`, `None`, `Ok`, `Error`) while
  still letting you use Haxe typing/tooling.

This page is inspired by the “Imperative lowering” docs in `haxe.elixir.codex`, but OCaml is closer to Haxe
than Elixir is: OCaml *does* have mutation (refs, mutable record fields, arrays), so the lowering can often be
direct instead of “imperative → purely functional”.

## Where this happens in the compiler

At a high level:

```
Haxe source (.hx)
  ↓ parse + type (Haxe)
TypedExpr (Haxe typed AST; already desugared by Haxe)
  ↓ macro-time compiler (reflaxe)
OcamlBuilder (TypedExpr → OcamlExpr)
  ↓ (some module-level scheduling, ordering, scaffolding)
OcamlASTPrinter (OcamlExpr → .ml text)
```

Key files:

- Lowering: `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx`
- OCaml AST: `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlExpr.hx`
- Printing/formatting: `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlASTPrinter.hx`
- Module emission + let ordering: `packages/reflaxe.ocaml/src/reflaxe/ocaml/OcamlCompiler.hx`

## Mental model

### 1) Haxe “statements” become OCaml “expressions”

OCaml is expression-oriented: most constructs produce values.
But a lot of imperative Haxe code is “statement-y” (e.g. assignments, method calls, `if` with no `else`).

To keep OCaml well-typed, `reflaxe.ocaml` frequently sequences expressions and discards intermediate values using
`ignore`:

- Haxe block `{ a(); b(); c; }` becomes an OCaml sequence:
  - `ignore (a ())`
  - `ignore (b ())`
  - `c`

### 2) Mutation is represented explicitly

In portable mode, mutable locals are lowered to OCaml `ref`s:

- reads use `!x`
- writes use `x := v`

For “instance fields”, we currently lower Haxe instances into OCaml records with `mutable` fields and use `<-`
for field assignment.

### 3) Loops are mostly direct, but `break`/`continue` need encoding

OCaml has `while`, but it doesn’t have statement-level `break`/`continue` keywords.
We encode them using exceptions local to the generated runtime module (`HxRuntime.Hx_break` / `HxRuntime.Hx_continue`)
and wrap loops in `try ... with`.

This mirrors the approach many compilers use when targeting languages without structured loop control.

## Common lowerings (portable / stdlib-first)

### Local variables: `let` vs `ref`

The backend scans a function/block and decides which locals are mutated:

- If a local is never assigned/updated, it becomes an immutable `let`.
- If it is assigned (including `+=`, `++`, etc), it becomes `let x = ref init`.

Example:

```haxe
var x = 0;
x = x + 1;
final y = x + 2;
```

Conceptually becomes:

```ocaml
let x = ref 0 in
ignore (x := !x + 1);
let y = !x + 2 in
...
```

Notes:

- This is a conservative, “portable semantics first” choice: Haxe allows mutation; OCaml needs an explicit mutable cell.
- `final` is naturally handled because it is (by definition) not mutated, so it becomes `let`.

### Assignments and update operators

Lowered forms:

- `x = v` → `x := v` when `x` is a `ref` local
- `x += v` → `x := !x + v`
- `++x` / `x++` → `x := !x + 1` (the value-position semantics are subtle; we validate common cases via fixtures)

For **field assignment** on instances:

- Haxe assignment is an *expression* that evaluates to the assigned value.
  To preserve this in OCaml (where `<-`/`:=` evaluate to `unit`), we commonly emit a temp:

  - `self.x = v` → `let tmp = v in (self.x <- tmp; tmp)`
  - `a[i] = v` → `let tmp = v in HxArray.set a i tmp` (since `HxArray.set` returns `tmp`)

- In statement position (most common), the backend wraps these in `ignore` so they can appear in OCaml sequences:
  - `ignore (let tmp = v in (self.x <- tmp; tmp))`
  - `ignore (let tmp = v in HxArray.set a i tmp)`

### Blocks and sequencing

Haxe blocks become sequences. Intermediate values are discarded using `ignore` to satisfy OCaml’s `unit` expectations.

This matters when you mix side effects with expressions:

- Prefer explicit intermediate bindings if you care about readability of emitted OCaml.
- Avoid deeply nested “side-effect expressions” when possible (the compiler has fewer options to emit clean code).

### `if` / expression-`if`

Haxe `if` lowers to OCaml `if ... then ... else ...`.

- If Haxe has no `else`, we emit `else ()` to keep the expression total.

### `while` loops

Haxe `while` maps to OCaml `while cond do body done`.

The body is a sequence expression, and we discard intermediate statement values with `ignore`.

### `break` / `continue`

We encode loop control using exceptions declared in `packages/reflaxe.ocaml/std/runtime/HxRuntime.ml`:

- `break` raises `HxRuntime.Hx_break`
- `continue` raises `HxRuntime.Hx_continue`

The lowering wraps loops like this (simplified):

```ocaml
try
  while cond do
    try
      body ()
    with
    | HxRuntime.Hx_continue -> ()
  done
with
| HxRuntime.Hx_break -> ()
```

Important details:

- `continue` is caught *inside* the loop body so it skips to the next iteration.
- `break` is caught *outside* the `while` so it exits the loop.
- `HxRuntime.hx_try` re-raises these exceptions so that Haxe `try/catch` does not accidentally swallow loop control.

### `for` loops

In practice, most Haxe `for` loops are already desugared by the time `reflaxe.ocaml` sees the AST:

- `for (i in 0...n)` often becomes a `while` + counter, or an iterator loop shape.
- `for (x in array)` becomes an iterator loop shape (`haxe.iterators.ArrayIterator`, etc).

So the backend mostly needs to handle the “lower-level” typed shapes (usually `TWhile`, iterator calls, and assignments).

### `switch` → `match`

Haxe `switch` becomes OCaml `match`.

Common patterns:

- Multi-case `case 1, 2:` becomes an OCaml or-pattern: `| 1 | 2 -> ...`
- Default becomes `_ -> ...`

#### Enum switches (important)

Haxe’s pattern matcher sometimes lowers enum switches into an “index switch”:

```haxe
switch (e) {
  case A:
  case B(x):
}
```

can become something like:

```haxe
switch (Type.enumIndex(e)) {
  case 0:
  case 1:
}
```

When we detect that shape, we reconstruct a direct OCaml match on the enum constructors and (when possible) bind
constructor parameters as pattern variables.

### Exceptions (`throw` / `try`)

Haxe exceptions are routed through a runtime wrapper so we can preserve:

- “throw any value” semantics (including primitives),
- predictable typed catches (`catch (e:T)`) for a useful set of types, and
- correct interaction with internal control-flow exceptions (`break` / `continue` / synthetic returns).

For the full strategy (typed catch matching, tagging, and `haxe.Exception` / `haxe.ValueException` behavior), see:

- `docs/02-user-guide/TRY_CATCH_AND_EXCEPTIONS.md:1`

Key points:

- `throw e` raises a dedicated runtime exception (`HxRuntime.Hx_exception`) carrying a boxed payload (`Obj.repr e`)
  plus best-effort type tags.
- `try/catch` lowers to an OCaml `try ... with` where:
  - internal control-flow exceptions are **re-thrown** immediately (so Haxe `try` never swallows loop control), and
  - typed catches are implemented by matching against the tag list (and runtime class tags when available).

### Escape hatch

You can inject raw OCaml using:

```haxe
untyped __ocaml__("(* ocaml here *)")
```

This is intentionally constrained (constant string only) and should be reserved for early bring-up or interop;
prefer a typed extern surface when something will be reused.

### Reflection note (portable)

Portable reflection is intentionally a “subset” feature: we support the pieces that unblock stdlib and common
libraries, but we do not try to match every edge of upstream reflection immediately.

Example: `Reflect.callMethod(obj, fn, args)` lowers to a runtime helper (`HxReflect.callMethod`) that performs a
best-effort dynamic apply based on the argument count.

## OCaml-native surface: how it changes the lowering

The OCaml-native surface is not a compiler “mode switch”.
It’s an **API choice**: you opt in by importing and using `ocaml.*` types.

Today, the compiler special-cases:

### `ocaml.List<T>` → native `[]` / `(::)`

Haxe:

```haxe
var xs = ocaml.List.Cons(1, ocaml.List.Cons(2, ocaml.List.Nil));
switch (xs) {
  case ocaml.List.Nil:
  case ocaml.List.Cons(h, t):
}
```

OCaml output becomes idiomatic list syntax:

- Construction uses `1 :: 2 :: []`
- Pattern matching uses `| [] ->` and `| h :: t ->` (conceptually)

### `ocaml.Option<T>` → native `None` / `Some`

Haxe `ocaml.Option.Some(v)` maps directly to `Some v`, and pattern matching uses `None`/`Some`.

### `ocaml.Result<T, E>` → native `Ok` / `Error`

Similarly, `Ok v` / `Error e` are emitted directly.

### What does *not* change (yet)

- Imperative Haxe code (mutation, loops) is still lowered the same way (refs + `while` + `try` wrappers).
- `ocaml.Ref<T>` is available as an **OCaml-native** opt-in surface:
  - `ocaml.Ref.make(v)` → `ref v`
  - `ocaml.Ref.get(r)` → `!r`
  - `ocaml.Ref.set(r, v)` → `r := v`
  This is separate from the portable “mutated locals → ref” lowering, which remains the default for ordinary Haxe code.

## Practical guidance: writing OCaml-friendly Haxe

Portable-first code that still generates readable OCaml:

- Prefer `final` locals and “data in/data out” helper functions when possible.
- Keep side effects on their own lines; avoid deep nesting of mutation inside expressions.
- Prefer `switch` with simple patterns; keep each case body simple and explicit.

OCaml-native code (when you want OCaml idioms):

- Use `ocaml.Option` / `ocaml.Result` instead of `null`/exceptions for domain-level error flows.
- Use `ocaml.List` when you want persistent lists and pattern matching idioms (and you’re okay with losing portability).

## If the output looks wrong

1. Reduce it to a tiny repro.
2. Add a snapshot case under `test/snapshot/` (golden output) and/or an `examples/` acceptance app if it’s behavioral.
3. Document the expectation and the intended idiom in hxdoc next to the code that performs the lowering.
