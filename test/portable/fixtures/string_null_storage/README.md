# String defaults and construction

This fixture keeps a missing String distinct from an initialized empty String.
Ordinary construction starts with null field defaults, then runs the authored
initializers. `new StringState()` therefore has an empty `empty` field.
`Type.createEmptyInstance(StringState)` skips those initializers, so all three
String fields remain null. The program checks both paths.

Run the complete fixture from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=string_null_storage npm run test:portable
```

The runner compiles and executes native OCaml and compares `expected.stdout`.
The additional checks inspect both generated allocation records, String carrier
decisions, callback output, and runtime dependencies. A second compilation must
produce the same lowering report. Upstream Haxe 4.3.7 JavaScript and Neko execute
the same source and must match the expected output.

The original output covers omitted, empty, and explicit-null fields and locals,
String calls, a nested callback, and a field write. The empty-instance assertion
adds a construction check without changing that output. This fixture does not
change README Goals or establish broader compiler compatibility.
