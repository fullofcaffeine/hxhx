# Null enum-abstract constants

Run `haxe test/m14_enum_abstract_initializer_test.hxml` from the repository root.
The test compares upstream Haxe with generated JavaScript and native OCaml.

Null is a resolved constant value, separate from an ordinary field or an unresolved initializer.
The fixture covers String, Int, Bool, and nullable String backing types, plus a same-enum alias.
Named and literal null patterns preserve their runtime behavior through a method parameter.
Statement switches and nested array patterns use the same selected constant values.
Integer zero and Boolean false remain distinct from null during matching.
Switch coverage does not require null as an additional missing value.
Native value switches here handle null explicitly; implicit results for unmatched null input remain outside this fixture.

The test also checks retained declaration types and constant identities.
Existing wrong-backing and ordinary-assignment rejection controls remain required.
README Goals status is unchanged; this fixture does not establish complete target parity.
