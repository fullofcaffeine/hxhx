# Nullable-string exceptions

This fixture throws `Null<String>` parameters, call results, and checked locals.
Text must reach a `String` catch. Null must skip that catch and reach `Dynamic`.
The fixture also checks rethrows, empty text, and exactly-once evaluation.

Run the native compile, execution, and report checks from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=nullable_string_throw bash scripts/test-portable.sh
```

Compare the independently authored expectation with upstream Haxe 4.3.7:

```sh
haxe -cp test/portable/fixtures/nullable_string_throw/src --run Main
```

The target uses its existing String representation, which also carries the
runtime null sentinel. The throw plan supplies only the `Dynamic` static tag.
The runtime adds `String` only when the actual value is text.
