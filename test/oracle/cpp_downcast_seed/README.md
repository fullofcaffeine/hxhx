# Native class downcasts

`Std.downcast(value, Child)` returns the original object when it belongs to
`Child`. A mismatching object or null input returns null. Narrowing must preserve
allocation identity, shared mutation, and the selected result type.

Run the managed regression:

```sh
npm run test:m14:cpp-downcast
```

The driver rejects an incompatible generic bound with upstream and local typing.
It checks declaration mutation, copied expression ownership, and preservation
of the selected result type. Native assertions cover matching classes,
inheritance, mismatches, null values, stored class handles, nested calls, and
ordered operands. The observer forces collection between operands and checks
exceptions, null class handles, and cleanup under ASan/UBSan at `-O0` and `-O2`.

Run the independent native references with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_downcast_seed -main Main -debug -cpp .tmp/downcast-upstream
.tmp/downcast-upstream/Main-debug
haxe -cp test/oracle/cpp_downcast_seed -main Oracle -debug -cpp .tmp/downcast-oracle
.tmp/downcast-oracle/Oracle-debug success
```

`Main` must exit successfully with empty stdout. Run `Oracle` with `success`,
`value`, `target`, `null-value`, and `null-target`. Compare each output with its
`expected.<mode>.stdout` file. The source operand runs first; a null source still
evaluates the class operand. An operand exception prevents later work.

The native observer verifies failure propagation and object lifetime, not Haxe
catch selection or exception wrapping. Full exception handling, broader generic
and target compatibility, performance evidence, combined CI, and integration
remain separate acceptance requirements.
