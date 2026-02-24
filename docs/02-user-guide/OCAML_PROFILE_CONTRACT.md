# OCaml Profile Contract (`-D ocaml_profile=portable|metal`)

This document defines the canonical OCaml profile switch used by `hxhx` Stage3 OCaml backends.

## Goal

Make profile selection explicit, deterministic, and backward compatible while we evolve portable/metal behavior.

## Accepted values

- `portable` (default)
- `metal`

Any other value is invalid and fails fast.

## Defaulting and normalization

- If `ocaml_profile` is missing or empty, it resolves to `portable`.
- Values are normalized to lowercase (`Portable` becomes `portable`, etc.).
- The normalized value is written back to the effective backend define map.

## Current semantics (today)

- `portable`:
  - current default behavior for OCaml emission.
  - intended to preserve existing Haxe-oriented portability expectations.
- `metal`:
  - reserved contract value for upcoming stricter native-oriented behavior.
  - currently recognized/plumbed but not yet behavior-divergent from `portable`.

## Scope

- The contract is enforced on Stage3 OCaml backend paths (`ocaml-stage3` and compatible OCaml wrappers).
- JS-native paths do not enforce this define.

## Failure behavior

Invalid values fail with an actionable message:

- `invalid -D ocaml_profile=<value> (expected portable|metal)`

## Examples

```bash
# default (portable)
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main

# explicit portable
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main -D ocaml_profile=portable

# explicit metal (contract-ready, behavior parity for now)
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main -D ocaml_profile=metal
```
