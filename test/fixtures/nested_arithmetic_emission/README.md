# Nested arithmetic emission

This independently authored program uses thirteen integer terms in one nested
expression. It also observes that its input function executes exactly once.
Both upstream Haxe and native OCaml must produce `expected.stdout`.

Run `haxe test/m14_nested_arithmetic_emission_test.hxml` from the repository root.
The normal `npm run test:m14:hih-dynamic-operators` command includes this check.

The regression prevents ordinary arithmetic from repeatedly rendering operands
for an inapplicable Dynamic operation. It preserves the original numeric
operations; it does not establish complete compiler performance or readiness.
Arithmetic directly on callback results and mutable static fields remain
separate open contracts (`haxe_ocaml-5wobl` and `haxe_ocaml-ailt8`).
