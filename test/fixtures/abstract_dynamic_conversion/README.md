# Abstract conversions through Dynamic

The abstract stores a class instance. Its authored conversion returns an integer
when a value enters `Dynamic`. The reverse conversion creates the class again.
Each operand and conversion prints a marker, so output checks expose missing or
repeated calls at local, assignment, argument, return and static-field boundaries.

Run `haxe test/m14_abstract_method_conversion_test.hxml` from the repository root.
The test compares upstream Haxe and generated JavaScript with `expected.stdout`.
JavaScript uses the complete real provider set. The companion native fixture
`../abstract_dynamic_output_native` verifies the five output-conversion boundaries.

The integer round trip remains blocked in C++ because the target does not bind
`Std.int` (tracked as `haxe_ocaml-nmki7`). Keep this source and expectation intact.
Reproduce that separate gap with complete real providers:

```bash
haxe -cp packages/hxhx-core/src -cp packages/hxhx/src -cp test \
  --run M14AbstractDynamicConversionTest test/fixtures/abstract_dynamic_conversion
```

The expected outcome is the same 17 lines. A missing native binding is a failure,
not accepted output or proof that integer recovery works.
