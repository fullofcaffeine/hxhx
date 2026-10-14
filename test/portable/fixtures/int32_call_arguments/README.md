# Int32 arguments to ordinary integer parameters

Haxe can retain the type `haxe.Int32` on an argument accepted for an `Int` parameter.
The OCaml call planner must preserve that conversion and the optional parameter convention.

This fixture formats Int64 fields through `StringTools.hex` and calls an ordinary method with required and optional integer parameters.
It covers a negative field, a supplied optional field, and an omitted optional argument with the minimum signed integer.
The native output and upstream Haxe output must match the independently written expected output.
The additional check requires separate sealed call plans and the expected optional boxing rules.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=int32_call_arguments bash scripts/test-portable.sh
```

This regression does not change README Goals status or prove full compiler bootstrap readiness.
