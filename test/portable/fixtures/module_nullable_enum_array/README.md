# Nullable enum array elements

Haxe permits a guarded nullable enum value as an argument to `Array<Choice>.push`.
Native OCaml must convert that value to the declared array element representation.
The conversion must preserve the mutable payload and evaluate the producer once.

`Holder` and `Collector` depend on each other. Their recursive module signatures
make an incorrect array element type fail during native compilation.
The fixture compares runtime output with an independent upstream Haxe expectation.
It also covers unshift, insert, contains, remove, and both forms of index lookup.
Concrete enum values entering nullable element storage retain their payload.
An effect log checks that the receiver runs once before the argument.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_nullable_enum_array bash scripts/test-portable.sh
```
