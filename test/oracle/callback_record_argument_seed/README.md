# Callback-containing values at Dynamic arguments

`npm run test:m14:callback-record-argument` checks that records and arrays containing
callbacks can cross a `Dynamic` call boundary. It rejects incompatible concrete
destinations and compares accepted source with upstream Haxe 4.3.7.

`ArgumentContract.hx` checks allocation identity, fresh literals, captured mutation,
and call counts through native C++ execution with forced collection and sanitizers.
`RecoveryContract.hx` checks that assignment through a structural view retains the
original value without inspecting its fields. It also checks callback replacement,
captured mutation, extra fields, and single evaluation through the same allocation.
Its wrong-shape values test assignment only. They do not assert that a later field
access or callback call is valid.
`ArrayRecoveryContract.hx` checks shared callback and Dynamic arrays, captured
mutation, and empty arrays. Its native-only cases check null results for non-arrays
and copies of fixed Int, Bool, and String arrays. Copies preserve boxed elements;
the contract never calls a non-function element. Float conversion is outside this
fixture. The shared-storage assertions use visible mutation, not a comparison
between differently typed array views.
`Main.hx` additionally recovers the values from `Dynamic` into typed record and
array locals. This unchanged program now passes native execution with forced
collection and both sanitizer profiles. Wrong-field access and equality between
differently typed structural views remain separate, unfinished requirements.

Run the independent upstream assertions with:

```sh
haxe -cp test/oracle/callback_record_argument_seed -main ArgumentContract --interp
haxe -cp test/oracle/callback_record_argument_seed -main RecoveryContract --interp
haxe -cp test/oracle/callback_record_argument_seed -main ArrayRecoveryContract --interp
haxe -cp test/oracle/callback_record_argument_seed -main Main --interp
```

The upstream programs succeed without output. Native upstream checks use Haxe 4.3.7 and
hxcpp 4.3.2 with `-cpp .tmp/callback-record-reference` instead of `--interp`.
Run the resulting executable for each main class.

The shared typing repair belongs to `haxe_ocaml-4irce`. It removes obsolete parsing
of arrows in displayed type names. Actual function signatures keep their existing
structural comparison. Native recovery is tracked by `haxe_ocaml-yll62`.
The remaining recovery contracts and PR92 integration remain required.
