# Array class values

The `Array` class literal can initialize `Class<Array<Bool>>`, appear as a
return value, or serve as a function argument. A stored concrete class handle
can widen to `Class<Array<Dynamic>>`. These operations preserve the same runtime
class descriptor; they do not convert an array or its elements.

Run the native compiler contract from the repository root:

```sh
HXHX_M14_SMOKE_GROUP=array_class_values haxe test/m14_cpp_runtime_class_value_test.hxml
```

The test loads real providers, checks ownership and rejected transfers, then
compiles and runs the generated C++ executable. Its output must match the four
lines in `expected.stdout`.

Upstream Haxe 4.3.7 reproductions:

```sh
haxe -cp test/oracle/cpp_array_class_value_seed/src -main Main --interp
haxe -cp test/oracle/cpp_array_class_value_seed/src -main Main -cpp /tmp/array-class-values
/tmp/array-class-values/Main
haxe -cp test/oracle/cpp_array_class_value_seed/negative -main Narrowing --interp
```

The final command must fail: a stored erased class handle cannot narrow to
`Class<Array<Bool>>`. Upstream reports `Dynamic should be Bool`. The positive
native observations used hxcpp 4.3.2. Expectations come from black-box source
and runtime checks, not upstream compiler implementation.

The contract also rejects copied runtime occurrences, unrelated class arguments,
and implicit conversion of actual array values. It does not prove general
reflection, constructor factories, or complete Haxe compatibility.
