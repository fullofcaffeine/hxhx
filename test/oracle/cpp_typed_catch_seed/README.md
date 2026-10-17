# Thrown values and ordered catches

This program checks which handler receives a thrown value and whether that value keeps its identity.
For example, an integral Float matches the earlier Int handler, while a fractional Float reaches the Float handler.
A child object keeps its identity through an interface catch, a base-class catch, mutation, and rethrow.

The program also checks unmatched propagation, exceptions thrown inside handlers, and break or continue from handlers.
Closures keep separate mutable catch variables after three handler executions.
An omitted catch annotation wraps an ordinary value in `haxe.ValueException`; an existing `haxe.Exception` keeps its identity.

The expected output comes from upstream Haxe 4.3.7 behavior.
Native `hxhx` C++ exception support remains unfinished under `haxe_ocaml-qrk0u`.
Capture lifetime remains separately owned by `haxe_ocaml-9jezt`.
This fixture does not establish full upstream-suite parity or native candidate acceptance.

Run the candidate contract with `haxe test/m14_cpp_typed_catch_test.hxml`.
It requires a native executable, the complete expected output, and unchanged original typed functions.
Unsupported parsing, typing, or emission remains a test failure.

Run these commands from the repository root with Haxe 4.3.7 and Neko available:

```sh
mkdir -p .tmp/cpp-typed-catch-oracle
haxe -cp test/oracle/cpp_typed_catch_seed/src --run Main > .tmp/cpp-typed-catch-oracle/eval.stdout
haxe -cp test/oracle/cpp_typed_catch_seed/src -main Main -neko .tmp/cpp-typed-catch-oracle/main.n
neko .tmp/cpp-typed-catch-oracle/main.n > .tmp/cpp-typed-catch-oracle/neko.stdout
diff -u test/oracle/cpp_typed_catch_seed/expected.stdout .tmp/cpp-typed-catch-oracle/eval.stdout
diff -u test/oracle/cpp_typed_catch_seed/expected.stdout .tmp/cpp-typed-catch-oracle/neko.stdout
```

With `hxcpp` 4.3.2 registered in the active library scope, compile and run the upstream C++ target:

```sh
HXCPP_COMPILE_THREADS=2 haxe -cp test/oracle/cpp_typed_catch_seed/src -main Main -cpp .tmp/cpp-typed-catch-oracle/cpp
.tmp/cpp-typed-catch-oracle/cpp/Main > .tmp/cpp-typed-catch-oracle/cpp.stdout
diff -u test/oracle/cpp_typed_catch_seed/expected.stdout .tmp/cpp-typed-catch-oracle/cpp.stdout
```

On an interactive host, apply the repository's background scheduling policy to the C++ build.
Use a local library scope when testing another `hxcpp` version, and retain its version with the results.

## Expanded behavior contracts

`NumericCatchMain` checks Bool, Int, Float, and String handlers independently.
Each row contains a four-bit acceptance mask in that order, followed by numeric handler selection and zero-sign observations.
The final two lines compare a typed Float before and after ordinary `Dynamic` conversion.
`RejectedNumericCatchOrderMain` must fail typing: a Float handler already covers Int, so a later Int handler is unreachable.

The expected files preserve differences between Haxe 4.3.7 targets.
On the observed hxcpp 4.3.2 build, integral Floats `-1`, `7`, and `255` match Int; `-2` and `256` do not.
Larger sampled integral Floats also differ from eval, and some differ from Neko.
This is not evidence for treating every integral Float as an Int.
Negative zero becomes positive at the C++ `Dynamic` boundary before throwing.
Eval and Neko preserve its sign in this program.

`WrapperCatchMain` checks explicit and implicit wrappers, handler order, identity, previous exceptions, native identity, and stack stability.
An explicit `ValueException` remains the value returned by a Dynamic catch.
An ordinary typed handler can instead receive that wrapper's payload.
A typed `ValueException` handler does not implicitly wrap an ordinary object; an omitted annotation does.
Wrapper construction calls the payload's `toString()` once, and rethrow does not repeat that conversion in these cases.
The observed default C++ build has no exception stack entries; eval and Neko have entries.
All three preserve the observed stack text across rethrow.

`RuntimeBoundaryCatchMain` checks EOF after full and partial reads.
Strings and ordinary exceptions named `Eof` must not become `haxe.io.Eof`.
This program does not yet test foreign C++ exception ingress or egress.

The native observations use Darwin arm64, Apple clang 17, Haxe 4.3.7, and hxcpp 4.3.2 without extra stack-trace defines.
Other hosts or flags need their own recorded comparison before these observations become a broader claim.
These programs remain upstream contracts, not proof that the candidate runtime implements them.

Run the complete upstream checks from the repository root:

```sh
python3 test/oracle/cpp_typed_catch_seed/check-upstream.py --target eval --output .tmp/cpp-exception-upstream-eval
python3 test/oracle/cpp_typed_catch_seed/check-upstream.py --target neko --output .tmp/cpp-exception-upstream-neko
```

For C++, enter a directory whose local haxelib scope registers hxcpp 4.3.2.
Keep the output inside that scope: Haxe invokes the native build from its output directory.
For the local scope shown below, run:

```sh
cd .tmp/cpp-catch-upstream-scope
HXCPP_COMPILE_THREADS=2 taskpolicy -b nice -n 10 python3 ../../test/oracle/cpp_typed_catch_seed/check-upstream.py --target cpp --output contracts
```

On hosts without `taskpolicy`, use the applicable background command from `AGENTS.md`.
The runner checks four complete programs and the rejected handler order.
It retains each command, status, stdout, and stderr, and never rewrites expected output.
Native programs compile sequentially into one directory to reuse hxcpp runtime objects.
Each child command has a 180-second limit; timeout cleanup owns the full child process group.

The candidate test now uses production classpaths and lazy dependency loading.
Its declarations and runtime type checks must come from the real standard library.
It remains red when parsing, typing, emission, native compilation, or runtime behavior is incomplete.
