# Default enum helpers

This program calls enum helpers without a `using` directive. It checks the
constructor index, payload, constructor name, and two receiver evaluations.
Upstream Haxe 4.3.7 supplies the independent behavior baseline.

Run the upstream program:

```sh
haxe -cp test/oracle/default_enum_extension_seed -main Main --interp
```

Run the candidate through the real JavaScript standard-library dependency chain:

```sh
haxe test/m14_default_enum_extension_runtime_test.hxml
```

The candidate test requires the actual `haxe.EnumTools` module, emits JavaScript,
and compares Node output with `expected.stdout`. It must not replace standard
providers with test declarations or omit their bodies to obtain a passing result.
Successful typing of the root module alone does not prove this runtime contract.
