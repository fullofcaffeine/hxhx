# Concrete values passed through inline Dynamic arguments

Haxe can insert a cast to `Dynamic` when it expands an inline function.
The OCaml output must convert the concrete value at that cast, before a
callee consumes its `Dynamic` representation.

This fixture preserves the original JSON call from a local function.
It also passes strings, booleans, integers, and null through a small inline
adapter to a separate consumer. The string-producing function must run once.
Native output must match the independent expected output and upstream Haxe.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=inline_dynamic_argument bash scripts/test-portable.sh
```
