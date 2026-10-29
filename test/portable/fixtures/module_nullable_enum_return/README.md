# Nullable enum method returns

Haxe permits a method declared to return `Choice` to return a `Null<Choice>`
producer directly. The OCaml method must convert the nullable storage back to
that exact enum representation. It must preserve null and payload identity.

`Holder` and `Projection` depend on each other. Their recursive OCaml module
signatures expose a missing return conversion as a native type error.
The fixture checks a mutable payload, a null result, and one producer call per
return. `test.sh` compares the independent expected output with upstream Haxe.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_nullable_enum_return bash scripts/test-portable.sh
```

This fixture covers the direct method return boundary. Nullable enum callback
arguments and comparisons have separate owners and tests.
