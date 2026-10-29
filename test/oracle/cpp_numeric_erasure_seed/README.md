# Float values stored through Dynamic

Haxe 4.3.7 with hxcpp 4.3.2 can change a Float's runtime kind when the value
enters Dynamic or Any storage. Exact integers from -1 through 255 become Int
values. Other tested Float values retain their Float kind. A typed Float return
preserves negative zero, while this conversion produces integer zero.

`Main.hx` checks that behavior through fourteen complete methods in
`NumericTransport.hx`. They cover returns, calls, closures, local initialization
and assignment, record fields, arrays, Map literals, Map mutation, and throws.
The reference checks half-step values from -4096 through 4096, integer limits,
boundary fractions, negative zero, NaN, and infinities. Expected output records
229,596 observations.

Build the native upstream reference with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_numeric_erasure_seed -main Main -cpp .tmp/cpp-numeric-erasure-reference
.tmp/cpp-numeric-erasure-reference/Main > .tmp/cpp-numeric-erasure-reference.stdout
diff -u test/oracle/cpp_numeric_erasure_seed/expected.stdout .tmp/cpp-numeric-erasure-reference.stdout
```

Run `npm run test:m14:cpp-numeric-erasure` for the candidate compiler. It emits
the complete authored methods and invokes them from an independent C++ observer.
The observer checks runtime kinds and values, typed negative zero, unchanged
Dynamic values, forced collection, and final cleanup. O0 and O2 builds use
address and undefined-behavior sanitizers.

The upstream reference also distinguishes runtime type membership and numeric
catch behavior. Those observations do not prove candidate support for numeric
catch handlers. Full exception acceptance, cross-host parity, combined CI, and
release evidence remain separate requirements. README Goals status is unchanged.
