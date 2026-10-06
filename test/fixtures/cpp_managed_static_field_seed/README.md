# Shared static fields

These methods write and read static fields through bare and qualified access.
Two classes use the name `value`; each keeps separate storage. An escaped closure
reads the current value after a later write. A local parameter named `value`
continues to refer to that parameter.

Run the independent source observer:

```sh
haxe -cp test/fixtures/cpp_managed_static_field_seed -main OracleMain --interp
```

Haxe 4.3.7 stdout must match `expected.stdout`. The observer assigns fields before
reading them. It does not establish default values or automatic startup ordering.

Run the managed C++ observer:

```sh
haxe test/m14_cpp_managed_static_field_test.hxml
```

The test emits these authored methods and their static payload through the
production managed emitters. It publishes the real runtime headers and compiles
an independent native observer at O0/O2 with strict warnings, ASan, and UBSan.
Both native executions must match the same expected stdout. Additional assertions
check collection during callbacks, retained arrays, replacement of an old array,
and preservation of the old field and result when a callback throws.

The observer explicitly publishes program storage before calling the source
methods. The generated slots start unassigned. The normal target still needs a
startup plan to publish storage, assign defaults, and run initializers in order.
This fixture proves field access and lifetime, not completion of that startup work.

The existing `test:m14:cpp-managed-closure-abi` npm command includes this test and
`M14TypedFieldOccurrenceTest`. The latter checks exact field ownership through
projection and rejects copied or removed occurrences and mismatched revisions.
