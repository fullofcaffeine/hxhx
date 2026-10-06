# Callback-containing values at Dynamic arguments

`npm run test:m14:callback-record-argument` checks that records and arrays containing
callbacks can cross a `Dynamic` call boundary. It rejects incompatible concrete
destinations and compares accepted source with upstream Haxe 4.3.7.

`ArgumentContract.hx` checks allocation identity, fresh literals, captured mutation,
and call counts through native C++ execution with forced collection and sanitizers.
`Main.hx` additionally recovers the values from `Dynamic` into typed record and
array locals. The runner retains both requirements. Recovery currently fails at
the explicit C++ storage-conversion boundary, so the complete command remains red.

Run the independent upstream assertions with:

```sh
haxe -cp test/oracle/callback_record_argument_seed -main ArgumentContract --interp
haxe -cp test/oracle/callback_record_argument_seed -main Main --interp
```

Both programs succeed without output. Native upstream checks use Haxe 4.3.7 and
hxcpp 4.3.2 with `-cpp .tmp/callback-record-reference` instead of `--interp`.
Run the resulting executable for each main class.

The shared typing repair belongs to `haxe_ocaml-4irce`. It removes obsolete parsing
of arrows in displayed type names. Actual function signatures keep their existing
structural comparison. Native recovery is tracked by `haxe_ocaml-yll62`. Recovery and PR92 integration remain required.
