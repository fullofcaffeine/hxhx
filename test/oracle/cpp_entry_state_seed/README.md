# Entry-class storage

The selected entry class must retain its fields and instance constructor.
The fixture checks initialization order, one-time effects, local shadowing,
qualified updates, a static method call, and access from another class.

Compare upstream output with `expected.stdout`:

```sh
haxe -cp test/oracle/cpp_entry_state_seed/src -main EntryStateMain --interp
```

Compile and execute the candidate C++ output:

```sh
haxe test/m14_cpp_entry_state_native_test.hxml
```

The native regression passes after restoring ordinary entry-class emission.
It also runs through `test:m14:cpp-native-backend-smoke:generated`.
Task `haxe_ocaml-1sf9g` retains broader validation and review requirements.
This fixture supplements the unchanged constructor and captured-initializer
fixtures; it does not replace either acceptance test.
