# Maps across recursive module interfaces

Two Haxe modules call each other through functions that accept and return maps.
The native interface must use the same map storage as the function bodies.
Returned maps retain identity and expose mutations through the original value.
Null and omitted optional arguments retain their existing behavior.

The fixture covers StringMap, IntMap with array values, ObjectMap with distinct
class keys, and nested Map abstracts. Equal fields in two object keys must not
make them the same key. The nested map checks replacement through an alias; the
array check mutates a stored array. Nullable Map abstracts, including a source
typedef, keep their existing boxed storage at argument and result boundaries.
Compile-time checks reject unsupported elements and unchecked private type names.

A function can also return either null or a concrete map from another module.
Both early and final returns preserve the original map, and the producer runs
exactly once when selected. The conversion keeps the nullable result storage
without copying the map or changing already-nullable values.

Calling methods directly on a nullable nested-map lookup remains separate work
under `haxe_ocaml-ud970`. This signature fixture does not claim that conversion
path works. Mixed nullable/non-null map equality is covered separately by
[`map_reference_identity`](../map_reference_identity/README.md).

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_map_signature bash scripts/test-portable.sh
```

The runner builds and executes native output, then compares upstream Haxe/eval
with the independently written expected output. Existing recursive-initializer
rejection and map runtime-identity tests remain separate checks.
This fixture does not establish complete native compiler promotion or speed gains.
