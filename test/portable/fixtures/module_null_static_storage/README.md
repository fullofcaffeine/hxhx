# Null static storage in recursive modules

A lazy service cache starts with null, then retains a callback record or a
service object containing typed callbacks. Cache and Peer call each other, so the generated
OCaml modules form a real dependency cycle.

The native executable and upstream Haxe must agree on lazy creation, repeated
identity, reset, and the behavior of previously returned values. The record
callback still works after the cache clears. A retained class instance keeps
its value and callback behavior after another instance replaces it.

The compiler retains the exact reference-cell type and admits only a checked
runtime-null initializer. This cell is not a safe recursion anchor. The AST
and module-assembly tests separately reject missing or mismatched types,
unchecked runtime names, arbitrary initializer calls, and unsafe cycles.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_null_static_storage \
  bash scripts/test-portable.sh
```

This fixture does not prove the complete compiler bootstrap or general eager
static initialization. Those require their own integration evidence.
The separate nullable-result limitation for optimized scalar-only classes is
tracked by `haxe_ocaml-jrmum`; this fixture models service
objects that contain callback records, as the original compiler cache does.
