# Nullable enum results from module-level functions

A module-level function can return a concrete enum through a declared
`Null<Choice>` result. Haxe stores these functions in a synthetic class.
The compiler must apply the same checked result conversion used for static
methods, including when an early return produces null.

This fixture returns a payload from another function, mutates the original
array, and observes the shared payload. It also exercises the null result.
The native program and upstream Haxe must produce the same expected output.
The lowering report must retain the enum identity proof for the conversion.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_nullable_enum_result bash scripts/test-portable.sh
```
