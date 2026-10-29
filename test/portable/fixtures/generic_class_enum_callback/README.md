# Enum callbacks passed to generic class methods

A `Mapper<T>` invokes a `T -> T` callback on its stored values. The caller
instantiates it with an enum and forwards a concrete callback through another
method. The native method stores generic callback inputs and results as
`Obj.t`, while the supplied function uses a native enum variant.

The fixture checks native compilation, callback inputs and results, repeated
invocation, null, array identity, shared mutable payloads, exception propagation,
and receiver-before-callback-producer evaluation. The portable runner compares
the native output with `expected.stdout`. The extra script checks the same
expectation with upstream Haxe and tests the typed conversion selector.

The selector must reject callback storage, return, identity comparison, and
replacement. It also rejects mismatched enum substitutions, a non-enum callback,
and an incomplete class hierarchy. Those cases cannot borrow the invocation-only
adapter proof. This fixture does not claim general callback storage support.

Run with `PORTABLE_FIXTURE_ALLOWLIST=generic_class_enum_callback bash scripts/test-portable.sh`.
