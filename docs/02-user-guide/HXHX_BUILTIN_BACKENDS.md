# HXHX Builtin Backends and Native Plugin Loading

Last audited: 2026-03-04

This page defines how backend selection works **after the CLI cutover**.

## Executive summary

- User-facing compile lane selection is done with:
  - `--ocaml`
  - `--ocaml-eval`
  - `--compat`
  - `--js <file>`
- `--target` is removed.
- `--target-id` is still valid, but only for plugin scaffold/build tooling (`plugin-init.sh`, `build-backend-plugin.sh`, promotion scripts).

## What is builtin vs plugin

- **Builtin backend**: backend implementation linked into the `hxhx` binary.
- **Backend plugin**: runtime-loaded provider from a manifest (`ocaml-dynlink` or `linked-provider`).

Current builtins in `hxhx`:

- `ocaml-stage3` (selected by `--ocaml`)
- `js-native` (selected by `--js <file>`)

## Current lane contract

### Native lanes

- `hxhx --ocaml ...`
  - routes to builtin backend `ocaml-stage3`
  - no stage0 delegation for runtime compile path
- `hxhx --js out.js ...`
  - routes to builtin backend `js-native`
  - preserves upstream JS flag semantics (`--js` consumes one output file argument)

### Delegated lanes

- `hxhx --ocaml-eval ...`
  - delegated macro/runtime lane through stage0 (`haxe`)
  - injects reflaxe OCaml bootstrap defaults
- `hxhx --compat ...`
  - pure passthrough to stage0 (`haxe`)
  - no hxhx-specific injection

### Removed flag behavior

- Legacy target-selection flags fail with a migration hint to direct flags.

## Native backend plugin kinds

Manifest kind options:

- `ocaml-dynlink`
  - native OCaml artifact (`.cmxs` for native host, `.cma` for bytecode host)
- `linked-provider`
  - provider type path compiled from Haxe sources

Canonical schema:

- `docs/02-user-guide/compat/hxhx-backend-plugin-manifest-v1.schema.json`

## Native plugin happy-path (auditable gate)

The CI gate proves end-to-end plugin loading and deterministic selection override.

Primary runner:

- `npm run test:hxhx:native-plugin-happy-path`

What it validates:

1. build plugin artifact + manifest,
2. load plugin manifest in native lane,
3. provider registration is observed,
4. backend selection switches to provider implementation,
5. emitted program output remains correct.

## Building plugin artifacts (tooling)

Scaffold and build tooling still uses provider IDs (`--target-id`) because plugin providers identify which backend ID they implement.

Example:

```bash
bash scripts/hxhx/plugin-init.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --target-id js-native

bash scripts/hxhx/build-backend-plugin.sh \
  --plugin-id demo.native.plugin \
  --kind ocaml-dynlink \
  --source-dir .tmp/promotion-demo \
  --dune-target demo_native_plugin.cmxs \
  --entry plugins/demo_native_plugin.cmxs \
  --target-id js-native \
  --out-dir .tmp/promotion-demo
```

Then compile using native JS lane + plugin manifest:

```bash
HXHX_FORBID_STAGE0=1 \
HXHX_TRACE_BACKEND_SELECTION=1 \
"$(bash scripts/hxhx/build-hxhx.sh)" \
  --js .tmp/promotion-demo/out/main.js \
  --hxhx-no-run \
  -cp src \
  -main Main \
  --hxhx-out .tmp/promotion-demo/out \
  -D hxhx_backend_provider=backend.js.JsBackend \
  -D hxhx_backend_plugin_manifest=.tmp/promotion-demo/backend-plugin.json
```

## Stage0-forbidden policy

With `HXHX_FORBID_STAGE0=1`:

- `--ocaml` and `--js <file>` remain valid.
- `--ocaml-eval` and `--compat` fail fast (by design).

Policy details:

- `docs/00-project/STAGE0_POLICY.md`

## Strict CLI mode

`--hxhx-strict-cli` enforces upstream-style CLI compatibility by rejecting hxhx-only extension flags.

Important nuance:

- `--js <file>` is still accepted (it is part of upstream CLI surface and native JS lane selection).

## Unsupported legacy targets

Legacy Flash/AS3 targets remain intentionally unsupported in `hxhx` native surface.

- `--swf`, `--as3` (and related legacy forms) fail fast with explicit diagnostics.

## Related docs

- `docs/01-getting-started/CHOOSE_YOUR_LANE.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
