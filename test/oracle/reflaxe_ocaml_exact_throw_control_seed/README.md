# Exact throw-control behavior oracle

This fixture records the user-visible exception behavior that upstream Haxe
4.3.7 already provides. An exact `Int`, `Bool`, or `String` value may cross a
function call before a matching source `catch` receives it. `Dynamic`,
`haxe.ValueException`, and `haxe.Exception` catches also receive the wrapper or
value required by Haxe, and rethrowing preserves the source value.

The null-String case is intentional. Haxe's `String` type is nullable in this
compatibility mode, but upstream Haxe 4.3.7 routes a null String to the
`Dynamic` catch rather than the `String` catch. The target therefore cannot
derive all catch tags from the static source type.

Run `npm run test:reflaxe-ocaml:exact-throw-oracle` to compare interpreter,
JavaScript, and Neko behavior with `expected.stdout`. The portable OCaml
fixture consumes this same Haxe source. The oracle establishes behavior only;
the reflaxe.ocaml implementation remains independently Haxe-authored and does
not copy upstream compiler code.
