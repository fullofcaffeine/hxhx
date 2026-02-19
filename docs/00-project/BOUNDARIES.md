# Project Boundaries

This monorepo contains multiple packages, but one product direction:

- `hxhx` is the primary compiler product.
- `reflaxe.ocaml` remains a first-class backend/runtime package.

## Package roles

- `packages/hxhx/`  
  CLI/product entrypoint and stage wiring.
- `packages/hxhx-core/`  
  Compiler core: parser, typer, resolver, lowering, backend contracts.
- `packages/hxhx-macro-host/`  
  Stage4 macro host process package.
- `packages/reflaxe.ocaml/`  
  OCaml backend/runtime package used by both user-facing target flows and bootstrap flows.
  It is also designed to stay usable with upstream Haxe.

## Strategic goals (boundaries-level)

- Keep `hxhx` implementation understandable and easy to modify.
- Reach upstream-compatible behavior for Haxe `4.3.7` workflows.
- Preserve clean-room MIT provenance for permissive commercial/embedded usage.
- Compile Reflaxe compilers/targets to native executables where practical for performance.

## Execution reality (today)

- Stage3 linked targets (`ocaml-stage3`, `js-native`) run through the native `hxhx` pipeline.
- Bootstrap builds are stage0-free by default when committed snapshots are available.
- Delegated compatibility paths still exist and are intentionally guarded.
- CI includes stage0-free smoke checks and upstream behavior-oracle gates.

## Provenance and licensing boundary

- Keep upstream compiler code as a behavior oracle, not a source tree dependency.
- Keep repository implementation content permissive-only.
- Keep `vendor/haxe` untracked and used only for oracle test runs.

## Repo split policy

- Keep monorepo until gate acceptance says packages are independently stable.
- Re-evaluate repository rename/split after replacement-readiness gates, not before.
