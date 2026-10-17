# Arrays, anonymous objects, and escaped callbacks

The program constructs arrays of objects and returns an object with a callback.
The callback returns the same array that the object stores. Field initializers
run in source order, even when the type lists field names in another order.

```sh
haxe -cp test/oracle/cpp_managed_aggregate_seed/src -main Main --interp
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

Upstream Haxe 4.3.7 must match `expected.stdout`. The native fixture loads the
real Array provider, then emits the five construction methods through the
production managed function emitter. It observes their results with independent
C++ checks under ASan and UBSan. Collection occurs before each managed allocation
and inside initializer callbacks.

The observer checks nested values, source evaluation order, shared identity,
creator exit, copied results, and cleanup after the final root leaves. A callback
also throws during the second child initializer. The previous caller result
must survive that failure. String cases include empty text, UTF-8 bytes, and an
embedded zero followed by ordinary characters.

Native record storage keeps an absent field distinct from a field with null.
This storage check does not establish Haxe optional-field access or reflection.
Field access in authored Haxe, iteration, and normal C++ target integration
remain separate requirements under `haxe_ocaml-9jezt`.
