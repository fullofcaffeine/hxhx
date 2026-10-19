# Native OCaml Array predicates

Run `npm run test:m14:ocaml-nominal-type-predicates` from the repository root.
The test compares upstream Haxe with an actual native OCaml executable.

Empty arrays and arrays stored in Dynamic retain their Array identity after mutation.
Null, primitives, and objects with a length field must return false.
The producer prints once before its predicate result, proving operand execution.

Shared typing inserts a representation-preserving cast around the Array type
argument. The OCaml target accepts only the retained certificate for that cast.
It then tests the existing private Array runtime marker. The source spelling
and public object fields cannot select that representation.

This contract belongs to `haxe_ocaml-wl89x`. Standalone class values and arbitrary
authored casts remain outside this predicate boundary. The test does not prove
the full exception-provider dependency closure or change README Goals status.
