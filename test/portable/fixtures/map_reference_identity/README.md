# Map reference equality

The same Map must compare equal after passing through a nullable argument and
return value. A different Map with identical entries must compare unequal.
Previously, native compilation rejected the nullable comparison because its
operands used different OCaml storage types.

This fixture checks both equality operators, both operand orders, nulls,
typedefs, nested functions, static initializers, and all supported Map key
families. Effectful operands must run once, from left to right.
The runner compares native output and upstream Haxe/eval with an independently
written expectation. The authored Haxe is unchanged between runs.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=map_reference_identity bash scripts/test-portable.sh
```

This is focused compatibility evidence. It does not prove complete native
compiler promotion or faster compilation.
