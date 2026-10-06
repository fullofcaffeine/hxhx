# Record reads and String equality

The fixture reads a required anonymous field and compares String values. Null
equals null but differs from empty text. Equality includes embedded zero bytes.

```sh
haxe -cp test/oracle/cpp_managed_record_read_seed/src -main Main --interp
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

The upstream program must match `expected.stdout`. The managed emitter compiles
the same five methods. An independent native observer checks
null, empty text, UTF-8, equality, inequality, and ordered callback effects.
Callbacks force collection; a throwing right operand must unwind the record.

Two methods initialize declared Dynamic fields from Boolean values, including a
nested record. The observer checks that each value keeps its Boolean identity
after collection. The shared typer must supply the declared field storage type
without replacing the child's original Boolean type.

Field selection uses the receiver's exact anonymous type. Native storage returns
a copied value into a root. Missing fields, nominal receivers, and copied source
expressions cannot acquire this binding. This is not dynamic reflection, optional
field support, property access, or general object equality.
