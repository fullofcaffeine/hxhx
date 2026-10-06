# Erased equality on C++

This program compares values stored as `Dynamic`. It records `==` and `!=`
separately because upstream C++ does not always return complementary results.
For example, both operators return false between a non-null String and a number.

`Main.hx` contains 69 values. Each output row contains a name, 69 equality bits,
and 69 inequality bits. The column order matches the source array. The matrix
includes null, Bool, Int, Float, String, object identity, closures, method values,
enums, and class values. Float cases include NaN, infinities, signed zero, and
Int32 boundaries. `Dynamic` is intentional here: erased comparison is the tested
language operation, not an implementation shortcut.

`expected.cpp.stdout` records Haxe 4.3.7 with hxcpp 4.3.2 on macOS arm64.
`expected.eval.stdout` records the Haxe 4.3.7 interpreter. These targets differ
on 292 of the 9,522 operator results. The native result is the C++ contract.
Keep both files so interpreter behavior cannot silently replace target behavior.

Run the independent upstream comparisons with:

```sh
node scripts/hxhx/cpp-dynamic-equality-oracle-seed.js
```

Set `HAXE_BIN` to Haxe 4.3.7 when it is not the default compiler. The selected
haxelib environment must provide hxcpp 4.3.2. The runner builds and executes
native code, compares both outputs, and retains artifacts under `.tmp/`.

Run the complete candidate regression with:

```sh
haxe test/m14_cpp_dynamic_equality_test.hxml
```

This regression remains incomplete. The candidate currently rejects a bare
static method value before emitting comparisons. Method selection and receiver
identity have existing tracked owners. Generic enum comparison also remains
unfinished. The temporary runtime diagnostic for enums does not count as parity.

The supporting command below exercises authored comparison functions with native
values, forced collection, and address/undefined-behavior sanitizers at O0 and O2.
It checks scalar observations, identity, operand order, and exception cleanup.
Its success does not replace the complete source regression.

```sh
haxe test/m14_cpp_dynamic_equality_values_test.hxml
```

## Upstream enum/null crash

`upstream_null_failure/DynamicEqualityProbe.hx` is a separate reduced input.
It compares an enum containing false with the same constructor containing null,
with both outer enum values stored as Dynamic. The interpreter prints false.
The observed native executable terminates with signal 11 (shell exit 139).

```sh
haxe -cp test/oracle/cpp_dynamic_equality_seed/upstream_null_failure \
  -main DynamicEqualityProbe --interp
haxe -cp test/oracle/cpp_dynamic_equality_seed/upstream_null_failure \
  -main DynamicEqualityProbe -cpp .tmp/cpp-enum-null-upstream \
  -D HXCPP_COMPILE_THREADS=2
.tmp/cpp-enum-null-upstream/DynamicEqualityProbe
```

This input documents an upstream failure, not an expected candidate crash.
The complete enum behavior and this unresolved boundary are tracked in
`haxe_ocaml-rirak`. Do not replace the crash with an invented equality result.
