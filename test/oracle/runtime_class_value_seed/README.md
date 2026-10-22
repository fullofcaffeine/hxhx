# Runtime class values

These fixtures check what happens when a program stores a class as a value.
They also check that an array returned through `Dynamic` still shares its original
storage after recovery. The expectations come from upstream Haxe 4.3.7, using
both its interpreter and Neko target.

The `names` fixture checks public and private secondary declarations, unknown
class lookup, and ordinary generic class identity. A compiler's module-qualified
declaration identity is not necessarily the public name returned by reflection.
The `Class<Dynamic>` comparison is a narrow metadata boundary for class handles
with different type arguments.

The `array` fixture returns one known `Array<Bool>` through `Dynamic`. The caller
checks array membership before recovery; its producer guarantees the element
type. Mutation and push must remain visible through both aliases. Null operands
and the Array class object itself are not array instances.

Run the native C++ contracts from the repository root:

```sh
haxe test/m14_cpp_runtime_class_value_test.hxml
```

The runner loads real providers, builds native output, and compares the executed
program with `expected.stdout`. It is registered in the core runtime-type-operands
test group. Current class-value rejection is a failing positive contract.

Check each upstream interpreter expectation:

```sh
haxe -cp test/oracle/runtime_class_value_seed/names -main Main --interp
haxe -cp test/oracle/runtime_class_value_seed/array -main Main --interp
```

For Neko, replace `--interp` with `-neko <output.n>`, then run `neko <output.n>`.
Compare stdout with the corresponding fixture's `expected.stdout`.

These cases do not prove specialized generic classes, numeric type predicates,
reflection factories, escaping closures, or full upstream-suite compatibility.
README Goals status remains unchanged.
