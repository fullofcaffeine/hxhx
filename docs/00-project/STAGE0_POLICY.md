# Stage0 Policy (Runtime / Build / Maintenance)

This project keeps stage0 usage explicit and bounded.

- **stage0** means an upstream `haxe` compiler binary used as a bootstrap tool.
- **runtime path** means running `hxhx` as a compiler for user workloads.

The policy goal is simple:

- Runtime behavior should be stage0-free for native lanes.
- Stage0 is allowed only for explicit bootstrap maintenance tasks.

## Policy table

| Lane | Allowed stage0 usage | Required guardrails | Typical commands |
| --- | --- | --- | --- |
| Runtime | **Forbidden** for stage0 delegation paths | `HXHX_FORBID_STAGE0=1`; fail fast if delegation is attempted | `hxhx --target ocaml-stage3 ...`, `hxhx --target js-native ...` |
| Build | Allowed only when explicitly requested | `HXHX_FORCE_STAGE0=1` for source regeneration/builds; otherwise use committed bootstrap snapshots | `bash scripts/hxhx/build-hxhx.sh`, `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh` |
| Maintenance | Allowed for maintainer-only bootstrap refresh and diagnostics | Explicit maintainer scripts; never implicit in normal runtime/release lanes | `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`, `bash scripts/hxhx/regenerate-hxhx-macro-host-bootstrap.sh` |

## CI enforcement

CI enforces this policy in the stage0-free smoke lane:

- `bash scripts/hxhx/check-stage0-policy.sh release`
  - builds `hxhx` with `HXHX_FORBID_STAGE0=1` and an invalid `HAXE_BIN` sentinel,
  - proves runtime delegation is blocked (`--version` fails fast),
  - proves native stage3 and macro-host selftest paths still work.

This keeps stage0 delegation failures explicit and reproducible.

## Release-path enforcement

`scripts/hxhx/build-dist.sh` defaults to strict stage0 policy:

- `HXHX_DIST_FORBID_STAGE0=1` (default) builds release artifacts with
  `HXHX_FORBID_STAGE0=1` and a non-existent `HAXE_BIN`.
- Any attempt to use a stage0 path in this mode fails fast.

If maintainers intentionally need a stage0-based dist experiment, they must opt out explicitly:

- `HXHX_DIST_FORBID_STAGE0=0 ...`

That opt-out is for debugging/maintenance only, not normal release policy.
