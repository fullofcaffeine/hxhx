# Interface calls and membership

This independently authored program checks that an interface view retains the
original object. Calls select direct, inherited, or overridden implementations.
Mutation through one view remains visible through another. Generic interface
parents retain their type arguments for calls and assignments.

The assertions also cover nulls, distinct objects, unrelated implementations,
receiver and argument order, and runtime membership through `Std.isOfType` and
`is`. A loaded but unused implementation must not enter the dispatch plan.

Run the upstream reference with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_interface_dispatch_seed -main Main -cpp .tmp/interface-upstream
.tmp/interface-upstream/Main > .tmp/interface-upstream.stdout
diff -u test/oracle/cpp_interface_dispatch_seed/expected.stdout .tmp/interface-upstream.stdout
```

Run the managed C++ regression:

```sh
npm run test:m14:cpp-interface-dispatch
```

The driver checks exact dispatch ownership, excludes unrelated and unreachable
implementations, and rejects attempts to emit an interface body. It then builds
and runs generated C++. The native observer forces collection and runs ASan and
UBSan at `-O0` and `-O2`. No temporary roots or allocations may remain afterward.

`FailureOracle.hx` independently observes a temporary receiver across an
allocating argument and failures from either operand. Compile it with
`-main FailureOracle`, then run `success`, `receiver`, and `argument` in that
order. Their combined stdout must match `expected.failures.stdout`.

For a null receiver, compile that observer with `-debug` and run `null`.
`expected.null-debug.stdout` records the native result: the argument executes
before `Null Object Reference`. On the observed macOS Haxe 4.3.7/hxcpp 4.3.2
release build, the same null call exits with signal 11. The interpreter raises
`Null Access` before the argument. Keep these target differences explicit.
The native managed observer checks null-call rejection, native operand order,
and root cleanup. Full Haxe catch selection and error wrapping remain separate
requirements; a native exception alone does not prove them.

This fixture does not establish full exception handling, generic method support,
or release readiness. The unchanged full typed-catch workload, broader tests,
performance evidence, review, CI, and integration remain separate requirements.
