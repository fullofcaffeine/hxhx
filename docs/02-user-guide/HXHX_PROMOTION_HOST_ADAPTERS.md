# Reflaxe Promotion Host Adapter Conventions (C6R2)

This document defines the generated host-adapter conventions for promoting a Reflaxe target into native plugin artifacts.

Scope:

- lane A: `hxhx` Stage3 native backend plugin host (`ocaml-cmxs`)
- lane B: upstream Haxe eval plugin host (`eval.vm.Context.loadPlugin`)

Compatibility target:

- workflow/contract compatibility (Level 1)
- **not** shared cross-host binary compatibility (a single `.cmxs` is not expected to run in both hosts)
- generated eval adapter manifests must keep `crossHostBinaryCompatibility=false`

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

- manifest kind is `ocaml-cmxs`
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

## Verification checklist

Use this checklist when scaffold generation lands:

- hxhx lane:
  - plugin manifest validates (`schema v1`)
  - Stage3 load smoke passes (`npm run test:hxhx:native-plugin-runtime-smoke`)
- eval lane:
  - eval smoke confirms `eval.vm.Context.loadPlugin` path is wired
- parity:
  - promoted backend wrapper emits equivalent artifacts vs builtin/provider pilot tests
