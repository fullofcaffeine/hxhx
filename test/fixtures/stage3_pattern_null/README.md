# Null access in switch patterns

Run `npm run test:m14:stage3-nested-patterns` from the repository root.
The test compares this program with upstream Haxe and the native OCaml executable.
Both must match the independently specified `expected.stdout`.

A later null pattern protects an array or object access only when earlier decisions still permit that case.
For example, `[[1]]` and `[null]` share an outer array length.
A `[null, _]` case has a different length and cannot protect that access.
The fixture also checks field-name order, failed-prefix short circuiting, sibling arrays, and single evaluation of the switched expression.
Generated temporary names must preserve authored locals.

The test driver separately requires an explicit rejection for an unsupported guard.
This is not evidence that guards execute correctly.
The null enum case does not prove construction or extraction of non-null enum values.
Full enum and alternative-binding coverage remain unfinished under `haxe_ocaml-yhvzj`.
