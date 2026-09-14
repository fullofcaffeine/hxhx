# Typed enum rethrows

This fixture catches and rethrows ordinary enum values and `haxe.io.Error`.
The outer catch must observe the same constructor and payload.

From the repository root, run the upstream behavior check:

```bash
haxe -cp test/oracle/reflaxe_ocaml_enum_rethrow_seed/src --run Main
```

Compare the output with `expected.stdout`. The expectation is independently
authored and checked against upstream Haxe 4.3.7.

The initial Reflaxe run fails before OCaml compilation at the first rethrow.
Issue `haxe_ocaml-fqx1x` owns the repair and integration into the target checks.
