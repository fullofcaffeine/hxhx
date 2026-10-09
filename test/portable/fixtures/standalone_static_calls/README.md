# Static initializer calls

An initializer can omit an optional argument or call a method that returns Void.
The compiler records these calls before generating OCaml, just as it does for a method body.
This fixture replaces the former optional-call and Void-call rejection cases in `call_exact_int_static`.

From the repository root, run the focused check with the pinned Haxe launcher:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=standalone_static_calls \
  bash scripts/test-portable.sh
```

The runner builds and executes the native program. Its additional check compares
upstream Haxe output and verifies the initializer call plans, including omitted-argument handling.
Missing, stale, replaced, and reset call plans remain covered by the call-plan unit fixture.
