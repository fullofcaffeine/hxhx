# Enum constructors with statement-valued arguments

A constructor argument can be a value that needs statements first: an array
comprehension, a `{ ... }` block, an `if`, a `switch`, a `try`, or a call to an
inline closure. Native Stage3 used to lose the constructor in that case and stop
with "OCaml emitter does not support runtime type operands for first-class type
values".

This fixture builds such values for a user enum, for a user enum that mirrors
`haxe.macro.Expr.ExprDef`, and for real `haxe.macro.Expr` values, as macro
reification does. It also nests constructors, passes several arguments whose
evaluation prints a line, and returns enum values from lambdas given to `map`.

Run `npm run test:m14:stage3-enum-constructor-control-arguments` from the
repository root. The test checks that upstream `haxe --interp` prints
`expected.stdout`, then emits the program through the native OCaml route, runs
it, and requires the same output, including argument evaluation order.

The closure-call argument uses a range loop, because native block closures do
not yet accept `for` over an array (haxe_ocaml-rwz23).
