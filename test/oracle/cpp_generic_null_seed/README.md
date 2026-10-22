# Generic null comparisons

A generic function must test the value supplied by its caller for null.
Its C++ template parameter name does not prove that the value is non-null.

Each line records `value == null`, `null == value`, `value != null`, and
`null != value`, in that order. A true result is `1`; a false result is `0`.
The cases cover absent and present integers, booleans, object references, and callables.
Zero, false, and an empty string remain non-null values.
Each operand passes through a counted function call.
A direct `if` condition must agree with each stored comparison result.
The final count proves that all 50 operand calls occurred exactly once.

Run the Haxe baseline:

```sh
haxe -cp test/oracle/cpp_generic_null_seed/src --run Main
```

Run the native C++ observer:

```sh
haxe test/m14_cpp_generic_null_comparison_integration_test.hxml
```

The generated-source C++ smoke runs this observer too.

The strict-local-binding fixture separately preserves the failing erased-value
case in the specialized `isOfType` renderer. Both contracts must pass before
the generic-null repair is complete.
