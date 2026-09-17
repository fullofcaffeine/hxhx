This fixture joins arrays inside and outside try/catch. It covers empty and
single-element arrays, integer and null conversion, nested arrays, null
separators, and object conversion exactly once in element order.

The owning test compiles the source with upstream Haxe's Neko target and both
hxhx Neko layouts, runs all three programs, and compares `expected.stdout`:

```sh
haxe test/m14_neko_typed_program_projection_integration_test.hxml
```

It does not prove every Array method, cyclic-array printing, or array mutation
through an earlier stored method reference.
