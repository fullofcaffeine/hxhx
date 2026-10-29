# Object keys retain their identity

An `ObjectMap` must find the same object after its fields or reachable values change.
For example, changing a key's revision must leave its stored value available.
Separately allocated objects remain separate keys, even with equal field values.
Copies share key objects but keep their map updates independent.

This fixture covers class instances, anonymous records, arrays, and empty class
instances from `Type.createEmptyInstance`. Map insertion must preserve class lookup
and virtual method calls. The method checks observe class behavior before and after
insertion without inspecting or changing a target runtime's object headers.

Run the upstream behavior check from the repository root:

```sh
haxe -cp test/portable/fixtures/object_map_mutable_identity/src -main Main --interp
```

Run the OCaml compile, build, and stdout comparison:

```sh
PORTABLE_FIXTURE_ALLOWLIST=object_map_mutable_identity bash scripts/test-portable.sh
```

The expected output specifies 23 successful observations. This focused contract
does not establish complete `ObjectMap` or target compatibility. Public README
readiness is unchanged.
