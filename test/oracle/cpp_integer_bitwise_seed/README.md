# Native integer bit operations

This fixture checks `&`, `|`, `^`, `<<`, `>>`, and `>>>` through authored Haxe and generated C++.
It covers signed 32-bit boundaries, zero and large shift counts, negative shift counts, and operand evaluation order.
The six compound forms also check stored results and a captured target changed by the right-hand side.
The target's old value must be read before those effects, then the completed result must be stored once.

`EvalMain` runs the shared integer assertions with upstream Haxe 4.3.7.
`Main` also checks native nullable operands: absent values contribute zero without changing the source value.
This nullable conversion is C++ target behavior, so the eval entry does not assert it.

Run the compiler regression with:

```sh
haxe test/m14_cpp_integer_bitwise_test.hxml
```

The test compares the shared assertions with upstream eval, emits and runs the complete native fixture,
and runs forced-collection AddressSanitizer/UndefinedBehaviorSanitizer observers at `-O0` and `-O2`.
It also rejects unrelated operand types and checks that emission preserves the authored typed function bodies.
The existing numeric-erasure test command includes this regression.

To verify the native reference with upstream Haxe and an installed hxcpp:

```sh
haxe -cp test/oracle/cpp_integer_bitwise_seed -main Main -cpp .tmp/cpp-integer-bitwise-upstream
.tmp/cpp-integer-bitwise-upstream/Main
```

Success produces no output. Reference checks use Haxe 4.3.7 and hxcpp 4.3.2.

On Apple clang 17, the original fixture at `9429c9b3e` exposed an unresolved, optimization-sensitive upstream native shift failure.
An array-driven upstream probe matches eval, and adding values to the failure message makes the full native program pass.
Issue `haxe_ocaml-gwee8` retains the reproduction and conflicting evidence; the full upstream native program is not accepted as passing parity evidence.

The hxhx contract masks shift counts to five bits and matches upstream eval for the full matrix.
Its native sanitizer checks retain all boundary assertions, including the cases that expose the upstream inconsistency.
Nullable numeric conversion is independently confirmed by the upstream native probe.
These assertions cover integer operators; they do not establish full Int64 integration or compiler readiness.
