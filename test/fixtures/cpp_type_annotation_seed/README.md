# Source type annotations retain their conversions

A type annotation such as `(value:Int)` uses ordinary assignment rules. It can
invoke an abstract's declared output conversion. A checked cast has a different
contract and must remain distinguishable throughout compilation.

This source tests a generic header conversion, an output method with a counter,
and a function whose argument type comes from its annotation. The expected
values are `7`, `8`, `1`, and `9`, in that order.

Run the upstream reference and the native C++ observer from the repository root:

```sh
haxe -cp test/fixtures/cpp_type_annotation_seed -main OracleMain --interp
haxe test/m14_cpp_type_annotation_test.hxml
```

The native observer reads the generated program's fields and forces collection.
Both `-O0` and `-O2` builds use strict warnings, AddressSanitizer, and
UndefinedBehaviorSanitizer. It does not rewrite generated source.

The companion shared-typing contract checks incompatible annotations, distinct
cast syntax, exact revision identity, selected conversion calls, callable
context, untyped permission, and preservation of an invalid annotation in a
macro quote:

```sh
haxe test/m14_source_type_annotation_test.hxml
```

The ordinary contextual-cast and managed-cast commands include these contracts.
This fixture does not prove general checked-cast runtime behavior or complete
standard-library compatibility. README Goals status is unchanged.
