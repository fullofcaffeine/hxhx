# Selected binary operations preserve values and operand order

This fixture uses bodyless abstract declarations for integer addition,
comparison, and boolean equality. It also calls a body-bearing unary helper.
The compiler must preserve each selected operation's exact storage contract.

The first comparison returns `false`; addition returns `12`. Reversing a
commutative declaration's parameter order still evaluates source operands
left to right, producing `11`. Compound addition writes `8` back to its local.
Boolean equality returns `false`, and the selected unary helper returns `-8`.
The effect sequence `1212312` checks source order and once-only evaluation.

```sh
haxe -cp test/fixtures/cpp_native_binary_operator_seed -main OracleMain --interp
haxe test/m14_cpp_native_binary_operator_test.hxml
```

An independent C++ observer reads the normal generated runner's storage after
forced collection. O0 and O2 builds use strict warnings, AddressSanitizer and
UndefinedBehaviorSanitizer. The C++ abstract-binary test command runs it before
the original broader fixture. General casts, generic operators, non-scalar
native conversions and Float behavior remain separate. README Goals are unchanged.
