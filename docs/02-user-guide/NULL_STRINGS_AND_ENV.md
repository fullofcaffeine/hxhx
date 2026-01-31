# Nullable Strings and Environment Variables (Portable Mode)

Haxe `String` is **nullable by default** (unless you enable strict null-safety).
In particular, `Sys.getEnv(name)` is specified to return `null` when the variable
does not exist.

OCaml strings cannot be `null`, so `reflaxe.ocaml` has to pick a representation
strategy for “nullable strings” in the generated OCaml code.

## Strategy used by reflaxe.ocaml (M6)

### 1) `null` is represented as an unsafe value (for `String` results)

When a runtime helper needs to return a nullable `String` (e.g. `Sys.getEnv`),
it returns:

- a real OCaml `string` when present, or
- an unsafe “null-like” value using `Obj.magic HxRuntime.hx_null` when missing

This mirrors how other targets behave: using a missing env var as a real string
without a null-check is a program error.

### 2) `Sys.putEnv(name, null)` is emulated via a reserved sentinel

OCaml 4.13 does not provide `Unix.unsetenv`, so we cannot truly remove an env var.
Instead, the runtime sets a reserved sentinel value and hides it from the Haxe view:

- `Sys.putEnv(name, null)` sets `name` to a sentinel value
- `Sys.getEnv(name)` returns `null` if the value is the sentinel
- `Sys.environment()` excludes sentinel entries
- `Sys.command(...)` uses `Unix.create_process_env` with a filtered environment so
  child processes do not receive sentinel entries

This is implemented in `std/runtime/HxSys.ml`.

## Tradeoffs

- This approach preserves the **Haxe-visible semantics** (`getEnv` nullability and
  `putEnv(null)` behaving like removal) without requiring a full “boxed string”
  representation across the compiler.
- The sentinel value is intentionally obscure, but it is not impossible for user
  code to set an env var to it. If you do that, the variable will be treated as
  removed by the Haxe view.
