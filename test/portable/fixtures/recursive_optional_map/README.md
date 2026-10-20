# Recursive optional Map arguments

An optional Map argument must retain its contents and identity when passed to a required Map parameter. This fixture puts both functions in one mutually recursive group. A concrete map literal constrains the required parameter to native Map storage.

Before the fix, the optional argument kept its nullable storage at the call. Native compilation failed because the required parameter expected a native map. Simpler nonrecursive calls could compile without exposing this conflict.

The fixture checks present and absent maps, a concrete map branch, recursion, shared mutation, and once-only argument evaluation. The portable runner compiles and runs the native output. The extra test compares the expected output with upstream Haxe.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=recursive_optional_map bash scripts/test-portable.sh
```
