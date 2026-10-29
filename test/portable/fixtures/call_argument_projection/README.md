# Call argument projection

The compiler projects checked argument slots without depending on their types.
An omitted slot receives a placeholder only when another operand follows it.
Trailing omissions stay absent, and a rest spread stays one unexpanded operand.

This fixture compiles the production helper through native OCaml and upstream
Haxe eval. Independent output checks cover internal and trailing omissions,
empty rest arguments, integer and string operands, shared object identity,
unchanged source arrays, and stale operand counts. A spread remains the same
array, and a mutation through the result remains visible in the original.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=call_argument_projection \
  bash scripts/test-portable.sh
```

The helper and slot enum depend only on positional data. The typed adapter
retains validation ownership. Full macro-host build and execution remain the
integration proof that this separation removes the original dependency cycle.
