This Neko-only fixture converts a number to a native string, slices it, and
constructs a Haxe String. It also checks an invalid range and an empty slice.
The expected results are independently specified in `expected.stdout`.

The owning test compiles this source with upstream Haxe's Neko target and with
both hxhx Neko output layouts. It runs all three programs and compares stdout:

```sh
haxe test/m14_neko_typed_program_projection_integration_test.hxml
```

This is a narrow primitive-boundary check. It does not establish the complete
Neko String API, exception stacks, or the byte-array standard library.
