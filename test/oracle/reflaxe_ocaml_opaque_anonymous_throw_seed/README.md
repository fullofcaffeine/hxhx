# Anonymous exception transport

This fixture throws a typed record that contains a nested object and an optional array.
The catch must receive the same object, including through a rethrow.
Missing fields must remain absent. Explicit null fields must remain present.
Nested mutations and array mutations must remain visible through aliases.

Run the upstream Haxe observer from the repository root:

```sh
haxe -cp test/oracle/reflaxe_ocaml_opaque_anonymous_throw_seed/src --run Main
```

Run native compilation and stdout comparison:

```sh
PORTABLE_FIXTURE_ALLOWLIST=opaque_anonymous_throw npm run test:portable
```

The fixture uses Dynamic only at the language exception channel and for arbitrary array elements.
The compiler must preserve their existing carriers without copying or inspecting them during a throw.
This does not authorize additional structural field operations.
