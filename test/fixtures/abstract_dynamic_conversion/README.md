# Abstract conversions through Dynamic

The abstract stores a class instance. Its authored conversion returns an integer
when a value enters `Dynamic`. The reverse conversion creates the class again.
Each operand and conversion prints a marker, so output checks expose missing or
repeated calls at local, assignment, argument, return and static-field boundaries.

Run `haxe test/m14_abstract_method_conversion_test.hxml` from the repository root.
The test compares upstream Haxe, generated JavaScript and native C++ with
`expected.stdout`. Both generated targets use complete real providers. The
companion fixture `../abstract_dynamic_output_native` checks the five output
boundaries separately.

The C++ target binds `Std.int` to recover the integer stored in `Dynamic`.
Run this native round trip separately with complete real providers:

```bash
haxe -cp packages/hxhx-core/src -cp packages/hxhx/src -cp test \
  --run M14AbstractDynamicConversionTest test/fixtures/abstract_dynamic_conversion
```

The expected outcome is the same 17 lines. Broader numeric and object coercions
remain partial; see `../../oracle/cpp_standard_int_seed/README.md` and
`haxe_ocaml-nmki7`. This regression does not establish full numeric parity.
