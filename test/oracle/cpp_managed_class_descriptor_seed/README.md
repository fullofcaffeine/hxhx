# Runtime class descriptor transport

Run `haxe test/m14_cpp_managed_class_descriptor_test.hxml`.

The authored source stores a class handle in a static field and returns that
class from a method. Upstream Haxe and the normal native C++ target must print
the same output. The standard type predicate checks an ordinary instance,
class handles, and null. Printed operand effects prove left-to-right evaluation.
A user method with the same name and signature retains its own false result.
Single and nested logical negation of predicate results match upstream output.
Class-handle equality and inequality preserve null and compare descriptor identity.
Printed comparison operands prove that each runs once, from left to right.
A separate generated native observer checks that the handle
and allocated instance storage use the same descriptor through copying and
collection. Both optimization levels use address and undefined-behavior sanitizers.
The observer checks equal and distinct addresses, including descriptors with equal
name text, and rejects a non-descriptor value at the checked storage boundary.
That low-level control does not authorize an authored conversion between unrelated
`Class<T>` arguments; such conversions remain a separate typing/storage contract.

Ownership checks reject foreign, copied, and mutated runtime-type occurrences.
Requiring a class handle records identity only. An explicit instance-layout check
must succeed before that descriptor can authorize native instance construction.
The runtime value test independently rejects identity-only instance allocation.

These checks establish descriptor transport, not general reflection or type-test
parity. The original erased-array alias fixture still needs its full native pass,
including public array push and length. Public reflection names remain owned by
shared typing under `haxe_ocaml-a1ueg`; no backend string rule supplies them.
