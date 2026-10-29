# Float literal observation

This corpus compares stored Float bits from upstream Haxe 4.3.7 eval and hxcpp 4.3.2.
`Main.hx` owns the constants. `Probe.hx` observes their bits without depending on decimal display formatting.

Run the interpreter with `haxe -cp test/oracle/cpp_float_literal_seed -main Probe --interp`.
Build native C++ with `haxe -cp test/oracle/cpp_float_literal_seed -main Probe -cpp .tmp/upstream-float-literals` and run the resulting Probe executable.

Coverage includes positive and negative zero, a fractional decimal, adjacent representable values, a subnormal, the smallest normal, and the largest finite value.
These observations do not prove Math, arithmetic, string parsing/formatting, JSON, serialization, or general Float comparison behavior.

`expected.bits.stdout` records ten constants and two values transported through local variables and a function return.
`DefaultProbe.hx` observes uninitialized storage separately. Its Dynamic local is an intentional observation boundary: native Haxe rejects a direct Float-versus-null comparison.
Default results can differ by target and must not replace the literal-bit expectations.

The default probe also covers nullable fields, out-of-range Array<Float> reads, and gaps after array growth.
The two `expected.default.*.stdout` files retain the target difference: native concrete Float storage uses zero, while eval preserves null.

Run `haxe test/m14_cpp_float_literal_integration_test.hxml` for production C++ emission and O0/O2 sanitizer observers.
The observer reads generated static storage without editing it and compares against the upstream bit corpus on two heaps.
It separately checks the native bit-copy primitive with Infinity and distinct quiet NaN representations. That primitive test does not establish Math or arithmetic parity.

The same command also emits the authored Float array read/write methods with the real Array provider.
This focused observer checks positive-zero gaps and preservation of an assigned negative zero after collection.
It does not replace the complete array-program regression.
