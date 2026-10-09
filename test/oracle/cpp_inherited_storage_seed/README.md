# Inherited instance storage

This program constructs a child class through its parent constructor. It changes
the inherited field through both child and parent references. Both references
must observe the same field, while the child retains its additional field.

Run the upstream behavior check:

```sh
haxe -cp test/oracle/cpp_inherited_storage_seed -main Main --interp
```

Success has no output. A failed assertion throws.

Run the native C++ check:

```sh
haxe test/m14_cpp_inherited_storage_test.hxml
```

The native test also runs with collection before every allocation at O0 and O2,
under AddressSanitizer and UndefinedBehaviorSanitizer. It checks that temporary
storage is released.

The fixture covers explicit nongeneric parent construction and inherited fields.
Generic class layouts, virtual methods, and the real exception provider remain
separate acceptance requirements. This fixture does not raise README readiness.

BareReceiver.hx checks implicit inherited reads and writes in a child constructor.
CapturedReceiver.hx retains that receiver in an escaping closure and observes
updates through the parent reference. Run their upstream checks separately:

```sh
haxe -cp test/oracle/cpp_inherited_storage_seed -main BareReceiver --interp
haxe -cp test/oracle/cpp_inherited_storage_seed -main CapturedReceiver --interp
haxe test/m14_cpp_inherited_receiver_test.hxml
```

Both receiver programs pass native execution and the O0/O2 sanitizer checks.
The captured case preserves the original local declared before assignment, the
escaping closure, and its explicit return. Checked storage rejects a read before
assignment while preserving later writes to the same captured location.

Task haxe_ocaml-71qn2 owns this storage change. The broader arrow contract in
haxe_ocaml-lg94m still requires parameter defaults and optional/rest behavior.
Shared definite-assignment diagnostics remain tracked in haxe_ocaml-mjz6e.
These focused results do not raise README readiness.
