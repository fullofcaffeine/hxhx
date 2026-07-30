# Reflaxe Promotion Host Adapter Conventions (C6R2)

This document defines the generated host-adapter conventions for promoting a Reflaxe target into native plugin artifacts.

Scope:

- lane A: `hxhx` Stage3 native backend plugin host (`ocaml-dynlink`)
- lane B: upstream Haxe eval plugin host (`eval.vm.Context.loadPlugin`)
- lane C: Stage4 native macro-module host (`macro.loadNativeModule` + `macro.runNativeExpr`)

Compatibility target:

- current manifest v1: workflow/contract compatibility (Level 1)
- current manifest v1 does **not** provide shared cross-host binary
  compatibility; generated eval adapter manifests must keep
  `crossHostBinaryCompatibility=false`
- planned M22 hard cutover: one versioned semantic ABI and target core for
  stock Haxe and `hxhx`, with exact generated host shells and a bounded
  one-container feasibility experiment

M22 implementation is currently deferred until Full1 and
`haxe_ocaml-38gsp.1` plus `haxe_ocaml-38gsp.2`. The adapter constraints below
define the future boundary; they do not claim that today's Stage3 builtin path
already runs the standalone `reflaxe.ocaml` target core.

Scaffold entrypoint:

```bash
bash scripts/hxhx/plugin-init.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --target-id js-native
```

Backend promotion entrypoint:

```bash
bash scripts/hxhx/promote-backend-plugin.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --provider-type backend.js.JsBackend \
  --target-id js-native
```

Eval-adapter promotion entrypoint:

```bash
bash scripts/hxhx/promote-eval-adapter.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --target-id js-native
```

Native macro-module dynlink smoke entrypoint:

```bash
npm run test:hxhx:macro-module-dynlink-smoke
```

## Hard-cutover naming contract

Generated promotion scaffolds should use this layout and names:

- `src/<targetNs>/core/<TargetName>Core.hx`
  - host-neutral target core logic only
- `src/<targetNs>/host/<TargetName>HostHxhx.hx`
  - `hxhx` host adapter (provider registration contract)
- `src/<targetNs>/host/<TargetName>HostHaxeEval.hx`
  - upstream eval host adapter (`loadPlugin` usage contract)
- `plugin/hxhx/backend-plugin.json`
  - Stage3 backend plugin manifest (`schemaVersion=1`)
- `plugin/hxhx/entry.ml`
  - native load entrypoint for `hxhx` host
- `plugin/haxe/entry.ml`
  - native load entrypoint for upstream eval host
- `plugin/haxe_eval/<module>.ml`
  - generated eval-adapter native entry module
- `eval-plugin.json`
  - Level-1 eval host manifest (`kind=haxe-eval`, `loadApi=eval.vm.Context.loadPlugin`)

Rule: generated files own host glue only. Target logic stays in `core/`.

## `hxhx` host adapter contract (Stage3 ABI)

The `hxhx` adapter must conform to Stage3 native registration ABI:

- manifest kind is `ocaml-dynlink`
- manifest `backend.entry` points to `.cmxs` (native host) or `.cma` (bytecode host)
- plugin load happens through:
  - `hxhx.BackendPluginManifestResolver`
  - `hxhx.NativeBackendPluginLoader`
  - `hxhx.NativeBackendPluginDynlink`
  - `hxhx.NativeBackendPluginHostAbi`

`plugin/hxhx/entry.ml` must register provider types as a load-time side effect using:

- runtime bridge: `HxHxBackendPluginHost.register_provider_type`
- row format consumed by Stage3 ABI parser: `<pluginId>\t<providerType>`

The Haxe provider type referenced by the row must expose:

- `public static function registrations():Array<BackendRegistrationSpec>`

Validation and failure semantics are enforced by:

- `packages/hxhx/src/hxhx/NativeBackendPluginHostAbi.hx`
  - pluginId mismatch: fail fast
  - duplicate provider type rows: fail fast
  - duplicate `implId` / descriptor conflicts: fail fast

Manifest kind policy:

- supported native manifest kind is `ocaml-dynlink` only.

## Upstream eval host adapter contract

The eval adapter is generated as a separate host lane.

Loader entrypoint contract:

- upstream macro/eval side uses `eval.vm.Context.loadPlugin(pluginPath)`
- adapter exposes host-callable plugin functions after load
- if local `haxe` and local OCaml toolchain ABI do not match, loading may fail with Dynlink errors; this is a host-toolchain constraint, not a promotion-schema issue

Adapter responsibilities:

- translate eval host callbacks into calls to the shared target core
- keep all host-specific runtime interaction contained in `HostHaxeEval`
- avoid leaking eval host types into target core modules

## Shared-core constraints

Promotion must keep one target core implementation reusable across both host adapters:

1. no codegen divergence between `HostHxhx` and `HostHaxeEval`
2. no host-specific state stored in core classes
3. host wrappers only map host ABI to core inputs/outputs

This keeps promotion as a packaging/load decision, not a backend rewrite.

## Planned M22 shared ABI and service-access presets

This is a future planning contract. Manifest/schema v1 and the commands above
remain current truth; no service-negotiation v2 API exists yet.

M22 requires stock Haxe and `hxhx` to implement one versioned semantic target
ABI and invoke one Haxe-authored target core. It separates three concerns that
are easy to conflate:

- execution: evaluated or native;
- service access: host-neutral or capability-integrated;
- activation: stock-Haxe plugin, `hxhx` plugin, or `hxhx` builtin.

The intended presets are evaluated host-neutral development, stock-Haxe native
plugin execution, `hxhx` native plugin execution, and integrated builtin
execution through `hxhx`. The two plugin forms use the same semantic contract
and target-core source identity, but may use different exact-host shells. Host
glue, `#if reflaxe_ocaml`, and native externs stay in adapters and composition
roots. The shared target core does not branch its semantic lowering by host.

Both plugin hosts implement the same typed/versioned capability negotiation.
`hxhx` may advertise additional privileged services. Missing required semantic
facts fail before target execution; optional optimization and tooling services
use their declared fallback or disablement. A missing stock-Haxe capability
does not authorize a different target implementation.

The supported reference toolchain compares one combined `.cmxs` with a shared
core plus exact host shells. A single container is an experiment, not the
semantic product requirement. Host shells may contain preflight, loading,
registration, value/schema conversion, request lifecycle, and error
translation. They may not contain lowering, printing, runtime selection,
mutation, output repair, or other target behavior.

The current upstream eval adapter remains the portable baseline until this hard
cutover lands. Its `crossHostBinaryCompatibility=false` field describes current
v1 artifacts only; it must not be interpreted as the future architecture.

Canonical plan:
`docs/00-project/REFLAXE_NATIVE_COMPILER_SDK_M22_PLAN.md`.

Accepted exact-host checkpoint:
`docs/00-project/ORACLE_CHECKPOINT_NATIVE_HAXE_PLUGIN_HOST_APIS_2026_07_29.md`.

## Verification checklist

Use this checklist when scaffold generation lands:

- hxhx lane:
  - plugin manifest validates (`schema v1`)
  - Stage3 load smoke passes (`npm run test:hxhx:native-plugin-runtime-smoke`)
- eval lane:
  - eval smoke confirms `eval.vm.Context.loadPlugin` path is wired
- parity:
  - promoted backend wrapper emits equivalent artifacts vs builtin/provider pilot tests
