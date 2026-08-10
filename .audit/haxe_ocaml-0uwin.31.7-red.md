# Expected red state: catch runtime-tag authority

Before the implementation changed, this focused command failed:

```text
npm run test:reflaxe-ocaml:catch-runtime-use
```

The relevant failure was:

```text
One exact Int catch must own one runtime-tag test before syntax is built.
```

This was the intended failure. The catch plan contained zero checked
`HxRuntime.tags_has` occurrences, even though an exact `Int` catch must test
one runtime tag. That proved the test was observing the missing planning fact,
not a later formatting detail or an unrelated native build failure.

The implementation then added the catch-owned occurrence and kept this test as
the focused regression. No generated OCaml file was edited to make it pass.
