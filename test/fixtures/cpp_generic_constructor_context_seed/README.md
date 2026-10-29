# Constructors in generic bodies

This program constructs concrete boxes from generic methods and field-initializer
closures. Int, Bool, String, and reference applications must preserve their values.
Nested closures, inherited fields, omitted constructors, explicit parent calls,
and omitted optional arguments exercise the same caller-owned type substitution.

Run `npm run test:m14:cpp-generic-constructor-context` for source-ownership checks
and native execution with address and undefined-behavior sanitizers at O0 and O2.
The independent observer forces collection, checks the retained payload, clears
its static owner, and verifies that both allocations are released.

Run `npm run test:m14:cpp-generic-storage-oracle` with the pinned Haxe 4.3.7 and
isolated hxcpp 4.3.2 toolchain described in `../cpp_generic_storage_oracle/README.md`.
The expected output is empty; authored assertions fail on incorrect behavior.

These focused contracts do not establish complete generic or Full1 compatibility.
README Goals status is unchanged.
