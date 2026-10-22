# Dynamic conditions in native C++

The same Dynamic value reaches an ordinary `if` and a guarded `switch`.
Each input therefore produces two output lines. Haxe 4.3.7 with hxcpp 4.3.2
produced `expected.stdout` with this command:

```sh
haxe -cp test/oracle/cpp_dynamic_condition_seed -main Main -cpp .tmp/upstream-dynamic-condition
.tmp/upstream-dynamic-condition/Main
```

The observed true cases are `true`, `1`, and `-1`. Null, false, zero, the tested
strings, an array, an anonymous object, and a function select false.

Run the local compiler comparison with:

```sh
haxe test/m14_cpp_dynamic_condition_test.hxml
```

The compiler must retain the checked condition occurrence before allowing a
Dynamic condition read. A copied expression or a stale function body cannot
authorize that conversion. The guarded-switch test checks these boundaries and
forced collection under address and undefined-behavior sanitizers.

Float and runtime type-descriptor conditions remain unsupported. The native
reader reports an explicit error for them. This fixture does not establish
general Dynamic conversion parity or change Full1 readiness.
