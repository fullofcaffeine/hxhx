This fixture checks ordered, once-only effects inside a value-producing block. A discarded Void call must not declare a parameter or shadow an authored local.

All state is local to `main`, so this fixture can test targets whose static initialization is still incomplete. The separate `sequencing_producer_seed` retains the static-field and method contract and its original expectation.

Run the upstream expectation with:

```sh
haxe -cp test/oracle/sequencing_local_seed/src -main Main --interp
```

Run a target with:

```sh
haxe test/m14_sequencing_native_integration_test.hxml lua local
```

Lua passes this local-only observer. Neko produces `10, 4, 1` because the
closure's counter writes do not update the caller's local variable.
That repair is tracked by `haxe_ocaml-3d14v`; the expectation remains `11, 4, 3`.
