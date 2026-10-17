# Array calls in initializers

Module and class field initializers use the same Array call plans as function
bodies. Comprehensions append their values in order. An explicit `push` call
evaluates its receiver before its argument and retains the returned length.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=standalone_array_calls PORTABLE_JOBS=1 bash scripts/test-portable.sh
```

The fixture builds and runs native OCaml. Its additional check compares upstream
Haxe output and requires the initializer calls and their runtime reasons in the
lowering report.
