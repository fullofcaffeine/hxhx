# Exact throw-control behavior oracle

This fixture records the user-visible exception behavior that upstream Haxe
4.3.7 already provides. An exact `Int`, `Bool`, or `String` value may cross a
function call before a matching source `catch` receives it. `Dynamic`,
`haxe.ValueException`, and `haxe.Exception` catches also receive the wrapper or
value required by Haxe, and rethrowing preserves the source value. The wrapper
cases distinguish four observable rules: primitive values receive one
`ValueException`, explicit `ValueException` and base `Exception` objects keep
their identities, and another `Exception` subtype skips an earlier
`ValueException` clause. An `Exception` clause also remains source-order
catch-all behavior even when a later concrete catch is present.

The nullable primitive cases freeze a subtler rule. A non-null `Null<Int>` or
`Null<Bool>` is caught by its concrete primitive type, but null skips that
catch and reaches `Dynamic`. The Bool case deliberately checks an earlier Int
catch so targets cannot rely on OCaml's ambiguous immediate representation.
The distinction also survives a function call and nullable-Int rethrow.

The null-String case is intentional. Haxe's `String` type is nullable in this
compatibility mode, but upstream Haxe 4.3.7 routes a null String to the
`Dynamic` catch rather than the `String` catch. The target therefore cannot
derive all catch tags from the static source type.

Run `npm run test:reflaxe-ocaml:exact-throw-oracle` to compare interpreter,
JavaScript, and Neko behavior with `expected.stdout`. The portable OCaml
fixture consumes this same Haxe source. The oracle establishes behavior only;
the reflaxe.ocaml implementation remains independently Haxe-authored and does
not copy upstream compiler code.
