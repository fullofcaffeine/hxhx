# Runtime Map type controls

This program checks different Map key families, null maps, an ordinary array,
and a user class named IntMap. An effectful Map producer must run exactly once.

```sh
haxe -cp test/oracle/cpp_map_runtime_type_seed/src -main Main --interp
haxe test/m14_cpp_runtime_type_map_test.hxml
```

The native test also retains the original thirteen-line arrow-map contract.
Its reduced fixture uses declaration-only Map providers to isolate the target
runtime connection. The constructor receiver tests separately use complete real
standard-library dependencies. Passing this reduction alone is not Full1 proof.

The `erased` program passes a Map through a `Dynamic` parameter. Upstream prints
`true`. C++ must reject this operation before replacing an existing artifact
until its erased storage preserves enough information to inspect Map identity.
This is an external runtime boundary in the fixture, not a domain-model shortcut.

```sh
haxe -cp test/oracle/cpp_map_runtime_type_seed/erased -main Main --interp
```

The positive C++ checks currently fail because shared typing still treats arrow
literals as arrays. This prerequisite is tracked in `haxe_ocaml-ale78`. Keep the
positive expectations while fixing that source owner; rejecting erased input
alone does not complete the native Map contract.
