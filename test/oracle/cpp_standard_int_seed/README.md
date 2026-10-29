# Native standard integer conversion

Run `haxe test/m14_cpp_standard_int_test.hxml` from the repository root.
The fixture checks truncation toward zero, signed zero, integer limits, numeric
values stored as `Dynamic`, unchanged input storage, nested calls, and operand evaluation count.
Its expected output comes from the Haxe API contract and independent upstream runs.

The driver loads real standard-library providers and emits the native C++ program.
It runs that program at `-O0` and `-O2`, with forced collection and address,
undefined-behavior, and float-cast-overflow sanitizers. Additional checks reject a
changed standard declaration and execute an authored replacement for `Std.int`.
The runtime observer also checks exception cleanup and unsupported inputs.
The existing numeric regression command includes this test through
`test/m14_cpp_numeric_erasure_test.hxml`.

| Input | Current C++ binding |
| --- | --- |
| Int or finite Float inside the signed Int32 range | Truncate toward zero |
| Numeric value stored as Dynamic | Use its actual numeric runtime tag |
| Null, including a nullable Float | Return zero, matching the native reference |
| Boolean stored as Dynamic | Return one or zero, matching the native reference |
| Float outside the signed Int32 range, NaN or infinity | `unsupported_diagnostic` before native narrowing |
| String or other object stored as Dynamic | `unsupported_diagnostic`; native coercion remains unfinished |
| Stored `Std.int` function value | Existing unsupported native-callable diagnostic |

The [Haxe 4.3.7 API](https://api.haxe.org/Std.html#int) leaves out-of-range and
nonfinite results unspecified. This binding rejects them instead of relying on an
unsafe C++ cast. It does not implement full `Std.int` parity. Remaining coercions
stay tracked under `haxe_ocaml-nmki7`. README readiness estimates are unchanged.

`reference/Main.hx` is an independently authored probe. `reference/observed.json`
retains 98 observations from pinned Haxe 4.3.7 and hxcpp 4.3.2 on macOS arm64.
Each invocation selects `typed` or `dynamic`, then one case from the source.
For example, with that toolchain installed:

```bash
haxe -cp test/oracle/cpp_standard_int_seed/reference --run Main typed negative_fraction
haxe -cp test/oracle/cpp_standard_int_seed/reference -main Main -cpp .tmp/std-int-reference
.tmp/std-int-reference/Main dynamic null
```

The probe records target differences rather than defining a portable coercion rule.
For example, native C++ returns zero for a Dynamic null; eval returns null.
Observed values for unspecified inputs are evidence, not promised semantics.
