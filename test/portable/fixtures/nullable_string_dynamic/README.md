# Nullable Strings at Dynamic boundaries

The same Haxe source prints both text and null through `Sys.println`.
Previously, native compilation passed a String directly to the print API's
Dynamic argument and failed OCaml type checking.

The fixture checks direct calls, stored values, and block results. A counter
proves that each producer runs once. The report checks that each nullable String
crossing has its own conversion from the existing String carrier to Dynamic.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=nullable_string_dynamic bash scripts/test-portable.sh
```

The runner builds and executes native output, then compares upstream Haxe/eval
with the independently written expectation.
