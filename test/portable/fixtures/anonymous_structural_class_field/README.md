# Class values in structural object fields

A field declared with a record-shaped type can receive a matching class.
Its methods must operate on the original instance, including inherited methods.
This fixture checks that conversion, once-only evaluation of a value-producing
call, an ordinary concrete class field, and an existing record value.

Run from the repository root with the Lix Haxe executable on PATH:

```sh
PORTABLE_FIXTURE_ALLOWLIST=anonymous_structural_class_field bash scripts/test-portable.sh
```

The runner compiles OCaml, builds and executes the native program, and compares
its output with the independently specified stdout. The extra check compares
that expectation with upstream Haxe eval. README goal readiness does not change.
