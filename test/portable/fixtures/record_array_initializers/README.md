This fixture constructs two objects with consecutive array fields and a scalar field.
Mutating the first object's arrays must preserve the second object's empty arrays.
Both objects must retain the scalar value after native compilation.

The regression produced an ungrouped OCaml `let` expression inside a record field.
OCaml consumed the next field separator as part of that expression and rejected it.
The shared AST printer must group the expression before joining record fields.

Run `PORTABLE_FIXTURE_ALLOWLIST=record_array_initializers npm run test:portable`.
Upstream Haxe 4.3.7 can check the expectation with
`haxe -cp test/portable/fixtures/record_array_initializers/src -main Main --interp`.
This fixture does not change README Goals readiness.
