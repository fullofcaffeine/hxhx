# Native abstract output conversions

An abstract with ordinary class storage returns an integer through its authored
conversion to `Dynamic`. The operand and conversion each print once. The checks
cover initialization, reassignment, arguments, returns and static fields.

Run `haxe test/m14_abstract_method_conversion_test.hxml` from the repository root.
The native observer loads complete real providers, builds a C++ executable and
compares its output with upstream Haxe and `expected.stdout`.

Integer recovery through `Std.int` is a separate native binding gap. The unchanged
round-trip fixture is retained in `../abstract_dynamic_conversion`; its README
provides the reproduction command. This fixture proves output conversion only.
