# Empty object constraints

These programs establish which values satisfy a generic `T:{}` bound in Haxe 4.3.7.
The bound requires an object-compatible type; it is not a wildcard for all values.
Classes, interfaces, records, arrays, strings, class values, and null are accepted.
Numbers, booleans, functions, enum values, and opaque abstracts are rejected.
An abstract with a declared conversion to an object is accepted.
Its underlying storage alone does not establish that conversion.

Run the upstream acceptance matrix:

```sh
python3 test/oracle/empty_object_constraint_seed/check-upstream.py
```

Run the shared-typer regression:

```sh
haxe test/m14_empty_object_constraint_test.hxml
```

The direct-call suite also executes `FeatureBoundEmptyObject` through generated JavaScript.
Run `haxe test/m14_direct_method_constraint_test.hxml`.
It checks object identity, a concrete returned method, and a String result.

This fixes a prerequisite of the valid `Std.downcast` call in the full typed-catch fixture.
It does not complete that fixture or general structural constraint support.
Nonempty structural bounds and authored conversion methods are outside this regression matrix.
The owning task is `haxe_ocaml-wnqhz`; README Goals status is unchanged.
