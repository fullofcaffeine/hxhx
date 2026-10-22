This fixture records Haxe 4.3.7 inline abstract method behavior. Run it with:

```sh
haxe test/m14_abstract_receiver_upstream_test.hxml
```

The test compiles and runs upstream Neko and JavaScript. It does not prove native hxhx support. Run `npm run test:m14:abstract-receiver` to also run the reduced native regression. Its direct and nested calls, field receivers, argument snapshots, early returns, and writes before throws pass in both Neko layouts and JavaScript. Indexed receiver parity and full standard-library validation remain unfinished.

An inline method substitutes caller storage for `this`. It must preserve each read and write, its return value, and its argument values. The output covers:

- An effectful field receiver: the argument runs first, then the receiver runs three times.
- An indexed receiver: the argument runs first; the read, write, and return revisit the array and index.
- An argument that replaces the caller's local before the body reads it.
- An early return and its normally completing alternative.
- A throw after mutation: the mutation remains visible to the catch's caller.
- An argument that aliases the receiver: its original value is retained across both writes.
- An unused effectful argument: its effect still occurs once.
- A throwing argument: the body and field receiver do not run.

The indexed assignment order differs between the two upstream targets. Both expected files retain those observed sequences. Do not merge them into a universal evaluation order or replace repeated storage accesses with one cached receiver.

These are independently observed upstream expectations. Native implementation must pass the corresponding target contract and the real standard-library tests before this task can close.
