# HXHX Scoped 1.0 Roadmap (Plain-English Guide)

This guide explains where we are in the `hxhx Scoped 1.0` journey without assuming compiler expertise.

Use this when you want to answer:

- What does “Scoped 1.0” actually mean here?
- How is Full 1.0 different?
- What is done vs still risky?
- Which bead/task tracks each milestone?
- How can I quickly verify progress myself?

## What “hxhx Scoped 1.0” means

For this project, `hxhx Scoped 1.0` means:

1. You can use `hxhx` as a practical Haxe compiler for Haxe `4.3.7` workloads.
2. Macro/tooling workflows work in native mode (not just by delegating to stage0 `haxe`).
3. We keep strict MIT-oriented provenance discipline (no copied upstream compiler/test sources in this repo).
4. The path to release is reproducible in CI and understandable by contributors.

Scope lock for release naming:

- `hxhx Scoped 1.0` is **core-first**: stage0-free runtime path, macro/plugin baseline, and production support for the explicitly supported targets.
- Additional non-legacy upstream targets land in follow-up waves (`1.1+`) instead of blocking the core `Scoped 1.0` label.

For strict Full 1.0 contract details, see:

- `docs/00-project/FULL_1_0_CONTRACT.md`

This is tracked primarily under epic: `haxe.ocaml-xgv.10`.

## How to read progress

Think of progress in layers:

1. Build confidence: can we build and regenerate the compiler reliably?
2. Core correctness: can we run upstream macro-heavy unit workloads?
3. Tooling/display correctness: can IDE/display paths run end-to-end?
4. Full orchestration: can native `RunCi` execute the full macro flow?
5. Hardening/productization: docs/layout/packaging/release quality.

If a lower layer is unstable, higher layers are not trustworthy yet.

## Milestone map (with beads)

### M0. Bootstrap and build reliability

Status: Done  
Bead: `haxe.ocaml-xgv.10.4`

Meaning in plain terms:

- Rebuilding/regenerating bootstrap artifacts no longer feels like a black box.
- Long steps have heartbeat/progress visibility and fail-fast behavior.

### M1. Core upstream macro unit workload

Status: Done  
Bead: `haxe.ocaml-xgv.10.1`

Meaning in plain terms:

- `hxhx` can run the central macro unit workload in a non-delegating mode.
- This gives us baseline confidence for front-end + macro-path behavior.

### M2. Display/tooling workflow bring-up

Status: Done  
Beads: `haxe.ocaml-xgv.10.3`, `haxe.ocaml-xgv.10.8`

Meaning in plain terms:

- Display-related workflows (used by IDE-like behavior) are reproducible in dedicated non-delegating rungs.
- We can test and debug display paths without needing full Gate2 completion.

### M3. Native RunCi orchestration progression

Status: Done  
Beads: `haxe.ocaml-xgv.10.11`, `haxe.ocaml-xgv.10.22`

Meaning in plain terms:

- The non-delegating Gate2 direct rung (`HXHX_GATE2_MODE=stage3_no_emit_direct`) now runs end-to-end with stable stage markers.
- Runner diagnostics now include `subinvocations=<n>` and `last_subinvocation=<cmd>` for faster triage.
- On macOS, direct mode now fails fast for `tests/misc/resolution` as well (no default stage skip fallback).
- Focused Gate2 display rung now reports `unsupported_exprs_total=0` (baseline refreshed on 2026-02-21).

### M4. Architecture hardening (target-agnostic core direction)

Status: Done  
Bead: `haxe.ocaml-xgv.10.5`

Meaning in plain terms:

- We published the first backend-layering design note and seam inventory: `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`.
- This is foundational portability work for long-term architecture quality and reduces risk as replacement criteria close out.

### M5. Product boundary cleanup in monorepo

Status: Done  
Bead: `haxe.ocaml-xgv.10.6`

Meaning in plain terms:

- Keep monorepo, but make product boundaries clearer (`hxhx` vs backend internals vs examples/tools).
- This improves contributor onboarding and future split options.

### M6. Gate3 stability hardening (real-world CI behavior)

Status: Done  
Beads: `haxe.ocaml-xgv.10.28`, `haxe.ocaml-xgv.10.29`, `haxe.ocaml-xgv.10.31`, `haxe.ocaml-xgv.10.32`, `haxe.ocaml-xgv.10.33`, `haxe.ocaml-xgv.10.34`, `haxe.ocaml-xgv.10.35`, `haxe.ocaml-xgv.10.36`, `haxe.ocaml-xgv.10.37`, `haxe.ocaml-xgv.10.38`

Meaning in plain terms:

- Gate3 `Js` now has deterministic retry controls (`HXHX_GATE3_RETRY_*`) for transient flake handling.
- Gate3 long-running targets now emit periodic heartbeat lines (`HXHX_GATE3_TARGET_HEARTBEAT_SEC`) and support explicit per-target timeouts (`HXHX_GATE3_TARGET_TIMEOUT_SEC`) so CI runs do not look hung.
- On macOS, `Js` server stage stays enabled by default, with deterministic timeout relaxation (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS`) instead of skipping the stage.
- Macro target now defaults to non-delegating direct execution (`HXHX_GATE3_MACRO_MODE=direct`) in Gate3 runners/CI.
- Python runs now default to no-install behavior (`HXHX_GATE3_PYTHON_ALLOW_INSTALL=0`) so local validation does not implicitly mutate host package state.
- Java target has validated baseline and forced sys-suite runs and is intentionally kept opt-in (not in default `Macro,Js,Neko`) to keep common Gate3 runs fast.
- C# has no-emit resolver evidence for native-library no-package externs; a full local C# target run still requires a host with `dotnet` or `mono`.
- Gate1, Gate2, and Gate3 now have weekly Linux scheduled baselines in CI, while PR/push CI remains fast.
- Linked builtin target smoke (`--ocaml` vs delegated `--ocaml-eval`) now has a reproducible runner and weekly/manual CI cadence.
- A debug escape hatch remains available (`HXHX_GATE3_FORCE_JS_SERVER=1`).

### M7. Replacement-ready acceptance

Status: Done (replacement bundle under current gate policy)  
Beads: `haxe.ocaml-xgv.10`, `haxe.ocaml-xgv.10.40`, `haxe.ocaml-ayi`

Meaning in plain terms:

- The replacement-ready acceptance gate is closed for the current documented scope/target policy.
- We now have a single replacement bundle runner (`scripts/hxhx/run-replacement-ready.sh`) with `fast` and `full` profiles so M7 evidence can be reproduced with one command.
- CI now runs `.github/workflows/gate-m7.yml` weekly in strict/full mode, and keeps manual `workflow_dispatch` controls for profile/strict overrides.
- This status does **not** mean strict stage0-forbidden closure for all replacement claims. For strict closure status, use:
  - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
- Current reproducible local fast path on macOS:
  - `HXHX_FORCE_STAGE0=0 bash scripts/hxhx/run-replacement-ready.sh fast`
  - Focused Gate2 display rung is now fail-fast (no Darwin-specific retry/skip fallback path).
- Scope reminder: this status is explicitly bounded to the supported target/gate policy documented in this guide and `README.md`.

### M16. Portable stdlib parity closure (hard Scoped 1.0 blocker)

Status: Done (for the declared Haxe 4.3.7 portable baseline scope)  
Bead: `haxe.ocaml-yfh`

Meaning in plain terms:

- We now track portable stdlib parity against a machine-readable baseline contract:
  - `docs/00-project/STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json`
- PR-lite scoping is pinned by a tiered allowlist contract:
  - `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_HAXE_4_3_7.json`
- Matrix statuses are driven by explicit evidence taxonomy:
  - `docs/00-project/STDLIB_PORTABLE_EVIDENCE_HAXE_4_3_7.json`
  - statuses: `override|runtime_backed|lowering_intrinsic|passthrough_verified|passthrough_unverified`
- Coverage status is generated into:
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
- Current matrix summary is fully closed for the baseline scope (`passthrough_unverified=0`):
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
- Missing-module closure is generated deterministically and auto-split into closure buckets under `haxe.ocaml-yfh.5`:
  - `docs/00-project/STDLIB_PORTABLE_CLOSURE_WORKLIST_HAXE_4_3_7.json`
  - `npm run stdlib:closure:generate`
  - `npm run stdlib:closure:sync`
- Current closure worklist is empty for this baseline (`missingModules=0`):
  - `docs/00-project/STDLIB_PORTABLE_CLOSURE_WORKLIST_HAXE_4_3_7.json`
- PR CI includes a fast stdlib parity lane; nightly/manual CI includes a broader parity lane.
- Portability lanes run with `ocaml_portable_native_surface=error` (local default remains `warn`).
- Scoped 1.0 is not considered complete until baseline portable stdlib parity closure is green for the declared scope.

Cross-check pages:

- Replacement strict/stage0-forbidden closure status:
  - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
- Portable stdlib parity evidence and per-module coverage:
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`

## Fast “where are we now?” commands

```bash
bd show haxe.ocaml-xgv.10
bd show haxe.ocaml-xgv.2
bd show haxe.ocaml-xgv.3
bd ready
```

Useful interpretation:

- `open`: not started
- `in_progress`: actively being worked
- `closed`: accepted against bead criteria

## Fast verification commands (high signal)

These are practical “confidence checks”, not full release proof:

```bash
npm run test:hxhx-targets
npm run test:upstream:runci-macro-stage3-display
npm run ci:guards
npm run test:stdlib:portable:tier1
HXHX_KPI_REPS=3 HXHX_KPI_RUN_MACRO_LANE=1 npm run hxhx:bench:kpi
HXHX_FORCE_STAGE0=0 bash scripts/hxhx/run-replacement-ready.sh fast
```

Why these checks:

- `test:hxhx-targets`: broad local regressions for staged compiler behavior.
- `runci-macro-stage3-display`: focused non-delegating display/Gate2 slice.
- `ci:guards`: license/provenance/version safety checks.
- `test:stdlib:portable:tier1`: portable stdlib baseline drift + portable fixture behavior checks.
- `test:stdlib:portable:tier1`: tier1 allowlist validation + strict portable fixture behavior checks.
- `hxhx:bench:kpi`: profile/plugin KPI report (compile, macro overhead, incremental, peak RSS).
- `run-replacement-ready.sh fast`: one-command M7 fast bundle evidence.

## Scope and expectations

Important: Scoped 1.0 here is not “all possible Haxe targets and every edge case forever.”

It is a concrete engineering bar tied to:

- explicit gates,
- explicit beads,
- explicit reproducible commands,
- and explicit MIT-provenance constraints.

As we close remaining blockers (especially Linux baseline non-delegating confirmations and distribution/performance gates), this document and `README.md` should be updated in the same change so non-experts can follow the journey.

Performance references:

- KPI baseline: `docs/benchmarks/HXHX_KPI_BASELINE.md`
- KPI thresholds: `docs/benchmarks/HXHX_KPI_THRESHOLDS.md`
- Post-Scoped 1.0 convergence policy: keep OCaml `portable` as default and track `upstream/portable/metal` deltas until portable performance converges to target budgets.
