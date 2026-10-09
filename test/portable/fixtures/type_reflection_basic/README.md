# Class lookup and identity

The fixture checks that a class value has its canonical package name, resolving
that name returns the same class value, and an unknown name returns null.
The expected output is independently written in `expected.stdout`.

Run the upstream reference with:

```sh
haxe -cp test/portable/fixtures/type_reflection_basic/src -main Main --interp
```

The existing portable runner uses `build.hxml`. The C++ runtime class-value
contract also reuses this source through
`haxe test/m14_cpp_runtime_class_value_test.hxml`. It loads real providers and
requires a native executable. That C++ implementation remains tracked in
`haxe_ocaml-sp2zl`; this fixture's upstream result does not establish C++ parity.
