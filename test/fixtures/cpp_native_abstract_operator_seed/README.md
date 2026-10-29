# Declared abstract operators keep their primitive storage

A bodyless `@:op(~A)` declaration tells Haxe to use integer complement for
this abstract. The compiler must evaluate the operand once and keep its
integer value while viewing it as the abstract type.

This fixture complements `7`. The expected output is `-8`, followed by `1`
for the operand's effect counter. An independent observer reads the original
generated program after forced garbage collection.

The remaining results check complement at both signed 32-bit limits, zero,
and negative one. A Bool-backed abstract also checks bodyless logical negation.
The expected results are `2147483647`, `-2147483648`, `-1`, `0`, and `true`.

```sh
haxe -cp test/fixtures/cpp_native_abstract_operator_seed -main OracleMain --interp
haxe test/m14_cpp_native_abstract_operator_test.hxml
```

The native check uses both O0 and O2, strict warnings, AddressSanitizer, and
UndefinedBehaviorSanitizer. The C++ abstract-unary command runs this fixture.
General casts, other result storage, floating-point behavior, and generic
operator support are outside this fixture. README Goals status is unchanged.
