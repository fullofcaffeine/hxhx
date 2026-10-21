# Copy an instance-owned map

An instance method copies a `StringMap` with key/value iteration. Both the key
and enum payload must survive. Updating the copy must leave the source unchanged.
An unrelated iterator returns ordinary records with the same `key` and `value`
fields. Those records must retain their object representation.

Inlining the map iterator can introduce an extra local variable. The OCaml
backend must retain the map's tuple representation through that unchanged alias.
Otherwise it reads tuple fields as anonymous-object fields and loses the entry.

Run the upstream behavior check from the repository root:

```sh
haxe -cp test/portable/fixtures/instance_map_pair_copy/src --run Main
```

Run the native compile, build, and stdout comparison:

```sh
PORTABLE_FIXTURE_ALLOWLIST=instance_map_pair_copy bash scripts/test-portable.sh
```

This focused regression does not establish full compiler or target-suite parity.
Public README readiness is unchanged.
