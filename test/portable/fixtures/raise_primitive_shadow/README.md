# User functions named raise

This fixture calls a Haxe function named `raise`, then catches a thrown string.
It also executes `continue` and `break` inside a `try` block. The expected output
proves that the user function still runs and that loop control reaches its owner.

Previously, generated catch branches resolved OCaml's exception primitive to
the user function. Dune rejected an internal exception where that function
expected a string. The OCaml expression printer now emits `Stdlib.raise` for
exception nodes while ordinary calls retain their resolved identifiers.

From the repository root, check the upstream Haxe behavior:

```sh
node_modules/.bin/haxe -cp test/portable/fixtures/raise_primitive_shadow/src \
  -main Main --interp
```

Run the generated native application through the portable runner:

```sh
PORTABLE_FIXTURE_ALLOWLIST=raise_primitive_shadow npm run test:portable
```

Both commands must produce `expected.stdout`. This fixture proves primitive
name ownership; it does not replace exception representation or Full1 tests.
