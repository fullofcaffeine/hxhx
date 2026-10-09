# Nullable integer operations in C++

The assertions cover null-preserving comparisons, C++ arithmetic on null,
prefix/postfix updates, compound assignment, captured writes, operand order,
and signed 32-bit wraparound.

```sh
npm run test:m14:cpp-nullable-integer
```

The native observer passes with forced collection, AddressSanitizer, and
UndefinedBehaviorSanitizer at O0 and O2. An earlier run timed out at 180 seconds.
A subsequent bounded run completed both sanitizer configurations. The harness
reports typed and emitted phase boundaries for diagnosis.

An independent upstream Haxe 4.3.7/hxcpp 4.3.2 parameter-based probe established
that null differs from zero in comparisons but converts to zero for integer
arithmetic and updates. Upstream interp instead throws for null arithmetic.
This target difference must remain explicit.

The full assertion program then built upstream but exited with signal 11.
Task haxe_ocaml-ftw61 retains the exact reproducer and requires a fresh-build
check and reduction. That failed reference run is not acceptance evidence.
Task haxe_ocaml-kk0df owns the managed operation changes. The original defaulted
arrow passes native execution and O0/O2 sanitizers. The optional arrow also
passes after shared nullable conditional lowering under haxe_ocaml-5aatj.
The full integer matrix now passes in the candidate. Nullable-to-scalar storage
transfers remain unfinished under the same task.

README Goals readiness is unchanged. These tests do not prove complete parity.
