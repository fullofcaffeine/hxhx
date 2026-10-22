# Standard Math constants

This fixture reads the standard Math constants through an import alias, static initialization, and a local variable.
A separate `shadows.Math.PI` field contains `7.0`. It must keep ordinary storage despite its matching short name.

Run the upstream observation with Haxe 4.3.7:

```sh
haxe -cp test/oracle/cpp_math_constant_seed -main Probe --interp
haxe -cp test/oracle/cpp_math_constant_seed -main Probe -cpp .tmp/upstream-math-constants
.tmp/upstream-math-constants/Probe
```

Use hxcpp 4.3.2 for the native comparison. The oracle reports exact bits for PI and the infinities.
It reports a NaN predicate because the NaN payload is not the public contract.

Run the managed backend test with `haxe test/m14_cpp_math_constant_test.hxml`.
The test emits and executes the authored program, then runs an independent C++ observer with sanitizers at O0 and O2.
The observer reads generated storage on two collecting heaps and checks the shadow field and root counts.
Ownership checks reject copied expressions, declarations from another program, writes through ordinary storage, and stale authored bodies.

This fixture does not establish general Math functions, arithmetic, equality, parsing, formatting, serialization, or Full 1.0 parity.
