# HXHX 1.0 Roadmap (Plain-English Guide)

This guide explains where we are in the `hxhx 1.0` journey without assuming compiler expertise.

Use this when you want to answer:

- What does “1.0” actually mean here?
- What is done vs still risky?
- Which bead/task tracks each milestone?
- How can I quickly verify progress myself?

## What “hxhx 1.0” means

For this project, `hxhx 1.0` means:

1. You can use `hxhx` as a practical Haxe compiler for Haxe `4.3.7` workloads.
2. Macro/tooling workflows work in native mode (not just by delegating to stage0 `haxe`).
3. We keep strict MIT-oriented provenance discipline (no copied upstream compiler/test sources in this repo).
4. The path to release is reproducible in CI and understandable by contributors.

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
- On macOS, intermittent `tests/misc/resolution` SIGSEGV can be handled deterministically via `HXHX_GATE2_SKIP_DARWIN_SEGFAULT=1` (default).

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
- Java target has a validated baseline run and is intentionally kept opt-in (not in default `Macro,Js,Neko`) to keep common Gate3 runs fast.
- Gate1, Gate2, and Gate3 now have weekly Linux scheduled baselines in CI, while PR/push CI remains fast.
- Linked builtin target smoke (`--target ocaml-stage3` vs delegated `--target ocaml`) now has a reproducible runner and weekly/manual CI cadence.
- A debug escape hatch remains available (`HXHX_GATE3_FORCE_JS_SERVER=1`).

### M7. Replacement-ready acceptance

Status: In progress  
Beads: `haxe.ocaml-xgv.10`, `haxe.ocaml-xgv.10.40`

Meaning in plain terms:

- All required gates and operational quality bars are green enough to claim practical replacement-readiness for targeted scope.
- We now have a single replacement bundle runner (`scripts/hxhx/run-replacement-ready.sh`) with `fast` and `full` profiles so M7 evidence can be reproduced with one command.

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
```

Why these three:

- `test:hxhx-targets`: broad local regressions for staged compiler behavior.
- `runci-macro-stage3-display`: focused non-delegating display/Gate2 slice.
- `ci:guards`: license/provenance/version safety checks.

## Scope and expectations

Important: “1.0” here is not “all possible Haxe targets and every edge case forever.”

It is a concrete engineering bar tied to:

- explicit gates,
- explicit beads,
- explicit reproducible commands,
- and explicit MIT-provenance constraints.

As we close remaining blockers (especially Linux baseline non-delegating confirmations and distribution/performance gates), this document and `README.md` should be updated in the same change so non-experts can follow the journey.
