# Array call evaluation order

An array call evaluates its receiver, then its argument, exactly once. Mapping
then invokes the callback in element order. Joining evaluates the separator once.
The expected output records those effects before the final string.

The portable planner integration test runs this authored source with upstream
Haxe and the native OCaml target and compares both with `expected.stdout`:

```sh
haxe test/m14_portable_auto_metalization_planner_integration_test.hxml
```

This fixture uses the real standard-library Array declaration. It also checks
that a copied call cannot borrow another expression's typed occurrence.
