# Generic constructors returned as interfaces

Run `haxe test/m14_generic_constructor_nominal_context_test.hxml`.
The harness compares independent upstream Haxe behavior with exact typed facts
and generated JavaScript executed in Node.

A constructor can infer its arguments from its operands or expected interface.
The result must retain the concrete class and its inferred arguments. An interface
with reordered parameters must constrain the corresponding concrete parameters.
Conflicting operand types and unrelated classes must reject.

Task `haxe_ocaml-4x0go` owns this inference boundary. Structural typedef resolution
remains separate work under `haxe_ocaml-pmsr1.1`; this fixture does not claim it.
