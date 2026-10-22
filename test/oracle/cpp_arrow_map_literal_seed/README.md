# Map literal runtime contract

This program checks integer, string, object, and enum keys, including object
identity and an ordinary array control. Its thirteen output lines must match
`expected.stdout`.

```sh
haxe -cp test/oracle/cpp_arrow_map_literal_seed/src -main Main --interp
haxe test/m14_cpp_map_runtime_type_inventory_test.hxml
haxe test/m14_cpp_runtime_type_map_test.hxml
```

The first command runs the upstream behavior reference. The inventory command
checks the four runtime tests authored in `Main` and their exact declaration
identities. It is not a native execution test.

The native test loads real standard-library declarations through the production
resolver. It checks generated C++ structure, builds an executable when the smoke
runner has a C++ compiler, and compares runtime output. Its additional control
program requires a native executable. All loaded modules remain subject to the
backend's publication checks; unsupported operations are failures even when they
occur in a dependency.

The previous fixture supplied four empty extern classes as provider substitutes.
Those declarations could not establish ordinary compilation or the Map literal's
exact shared type. They have been removed from this native path. Passing a reduced
declaration test must not be used as native Map readiness evidence.

Work remains tracked in `haxe_ocaml-ale78` and `haxe_ocaml-0i4lh`. Root typedef
resolution has the existing owner `haxe_ocaml-pmsr1.1`.
