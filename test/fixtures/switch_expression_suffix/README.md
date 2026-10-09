# Switch operand suffixes

Run `haxe test/m14_switch_expression_suffix_test.hxml` from the repository root.
The fixture checks that a switch operand can continue after parentheses with an
array index. Upstream Haxe and generated JavaScript must print `zero` and `other`.

`Shapes` separately asks upstream Haxe's macro API to parse three expressions.
The parser must preserve one pair of parentheses, nested parentheses, and an
indexed parenthesized operand. `ShapeMacro` observes source syntax; it does not
provide compiler implementation or substitute a runtime library.

This is the reduced grammar used by JavaScript's real `Type.hx` provider.
Task `haxe_ocaml-eap2q` owns the parser fix. This test does not establish Full1 parity.
