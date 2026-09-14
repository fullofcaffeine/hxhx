This fixture initializes an object through a constructor with an explicit
`:Void` result. It reads a field, catches a field read on null, then reads the
valid object again. The expected output is `present`, `NPE`, and `present`.

Run the owning integration test to compare upstream Haxe's Neko target with
both generated Neko layouts:

```sh
haxe test/m14_neko_typed_program_projection_integration_test.hxml
```

The check proves that ordinary null field access throws. It does not constrain
exception message text, reflection, or null-safe access.
