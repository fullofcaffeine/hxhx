# Native integer remainder

Run `haxe test/m14_cpp_integer_remainder_test.hxml` from the repository root.
The numeric-erasure test group also runs this regression.

The program checks exact Int remainder, both mixed nullable forms, and two
nullable operands. It covers signs, minimum Int modulo minus one, zero divisors,
null operands, single evaluation, operand order, typed handler order, unmatched
propagation, and String rethrow. The test rejects Float, Dynamic and unrelated
operand types. It also rejects remainder through the arithmetic emitter that
has no rooted exception context.

The selected native contract throws the String `Mod by 0 Error.` for an exact
Int zero divisor. With a nullable operand and Int result, zero divisors yield
zero. This difference is observed with Haxe 4.3.7 and hxcpp 4.3.2. It must not be
extended to Float results or erased Dynamic operations.

## Upstream profile discrepancy

Classification: `known_divergence` for the optimized upstream minimum-Int case.
On macOS ARM, the initial assertion program passed the upstream debug build but
failed its minimum-Int-modulo-minus-one assertion in the optimized build.
Separate native runtime-input and printed-value probes observed zero. The
profile difference does not by itself prove the upstream failure's cause.
The independent expectation remains zero, and this test requires that result
at O0 and O2 with address and undefined-behavior sanitizers. It does not claim
strict equivalence to the failing optimized upstream observation.

Use the isolated hxcpp setup in the
[upstream startup observer](../../fixtures/cpp_static_startup_oracle/README.md).
Compile this directory with `-main Main -cpp <output>` and repeat with `-debug`.
The program should exit zero without output for the selected contract. Retain
an optimized upstream failure separately; do not relabel it a pass. Eval has a
different zero-divisor behavior and is not the oracle for these native cases.

The local test checks original typed-source revisions and repeats execution
under forced collection. General exception support, Float remainder, compound
remainder assignment, and Full 1.0 readiness are separate contracts.
