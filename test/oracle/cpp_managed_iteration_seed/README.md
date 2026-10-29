# Managed Array iteration

The fixture checks Array iteration across callbacks, nested loops, and escaping
closures. Each captured loop variable must retain its own iteration's value.

```sh
haxe -cp test/oracle/cpp_managed_iteration_seed/src -main Main --interp
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

Upstream Haxe 4.3.7 must match `expected.stdout`. The native fixture emits the same
methods through production managed function and closure emission. An independent
C++ observer forces collection during callbacks and captured-cell allocation.

The loop selects its iterable once. It reads the current array length at each
test, so callbacks can append elements or replace later values. Break, continue,
early return, and exceptions retain their source behavior. Nested loops have
separate retained arrays and positions. No borrowed vector element survives a
callback.

Saved closures return 4 and 6 after the loop and its creator exit. Replacing the
original array's first element must not change either captured integer. A callback
also produces a fresh array with no external owner; the loop must retain it.
The observer checks that collection releases all graphs after their roots leave.

The fallback return exposed missing unary Int negation. It uses the existing
widened subtraction and 32-bit wrapping rule. Native checks include the minimum
and maximum Int values. Float operations are outside this fixture.

This boundary currently admits lowered Array value loops. Key/value iteration,
general iterators, and ordinary root-statement loops still need their exact plans.
It does not establish the normal C++ target cutover or complete iteration parity.
