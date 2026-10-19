# Native enum-value reflection

`Reflect.isEnumValue` recognizes enum instances, including constants and constructors with payloads.
An enum type descriptor is not an enum instance. Primitive values, objects, arrays, functions, and null must also return false.

Run `haxe test/m14_stage3_is_enum_value_test.hxml` with the repository Haxe toolchain.
The fixed expectation is checked against upstream Haxe and the generated native executable.
The producer marker proves that the predicate evaluates its argument once.

The native forwarding module delegates to the existing HxReflect runtime function.
This fixture does not establish complete reflection or exception-provider readiness.
