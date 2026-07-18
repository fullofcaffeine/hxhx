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

- Stage3 native lanes (`--ocaml`, `--js <file>`) run through the native `hxhx` pipeline.
- Bootstrap builds are stage0-free by default when committed snapshots are available.
- Delegated compatibility paths still exist and are intentionally guarded.
- CI includes stage0-free smoke checks and upstream behavior-oracle gates.
- Stage0 usage boundaries are documented in `docs/00-project/STAGE0_POLICY.md`.

## Provenance and licensing boundary

- Keep upstream compiler code as a behavior oracle, not a source tree dependency.
- Keep repository implementation content permissive-only.
- Keep `vendor/haxe` untracked and used only for oracle test runs.
- Follow stdlib sync boundary rules in `docs/00-project/STD_LIB_POLICY.md`.
- Follow clean-room shipping rules in `docs/00-project/PROVENANCE_POLICY.md`.
- ML2HX/translation experiments are explicitly non-shipping.

## Repo split policy

- Keep the monorepo today while making `reflaxe.ocaml` independently
  buildable, testable, packageable, and releasable.
- Do not split on a date or version milestone alone. Require the technical
  extraction gates plus a measured ownership, release, or maintenance benefit.
- After a future split, keep `hxhx` as a pinned downstream compatibility and
  end-to-end workload for `reflaxe.ocaml`, without making it the target's only
  correctness or release gate.
- The controlling decision, coupling inventory, migration sequence, and
  post-split QA tiers are in
  `docs/00-project/REFLAXE_OCAML_REPOSITORY_EXTRACTION_GATE.md`.
