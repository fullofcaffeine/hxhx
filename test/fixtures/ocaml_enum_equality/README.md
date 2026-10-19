# Native enum equality

`Type.enumEq` compares enum constructors and their payloads, including nested enum values.
Ordinary object payloads retain identity comparison; Boolean and integer Dynamic values remain distinct.

Run `haxe test/m14_stage3_enum_equality_test.hxml` with the repository Haxe toolchain.
The fixed expectation is checked against upstream Haxe and the generated native executable.
The fixture covers constants, unequal constructors, primitive and recursive payloads, null payloads, object identity, and operand evaluation order.

The native carrier observer also rejects different enum names with equal native tags and unboxed values that lack enum identity.
Its raw-variant controls preserve the existing standalone runtime helper's behavior.
This fixture does not establish complete reflection or standalone recursive enum parity.
