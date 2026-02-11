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

Status: In progress  
Bead: `haxe.ocaml-xgv.10.11`

Meaning in plain terms:

- We can compile and launch upstream `RunCi` in native Stage3 mode.
- Remaining gap: it still stalls early in some flows and does not yet complete the full expected macro-stage journey reliably.

This is the current highest-priority technical blocker for “replacement-ready” confidence.

### M4. Architecture hardening (target-agnostic core direction)

Status: Open  
Bead: `haxe.ocaml-xgv.10.5`

Meaning in plain terms:

- Document how to reduce OCaml-specific coupling in the HIH core over time.
- Important for long-term portability and cleaner architecture, but not the immediate blocker for current Gate2 bring-up.

### M5. Product boundary cleanup in monorepo

Status: Open  
Bead: `haxe.ocaml-xgv.10.6`

Meaning in plain terms:

- Keep monorepo, but make product boundaries clearer (`hxhx` vs backend internals vs examples/tools).
- This improves contributor onboarding and future split options.

### M6. Replacement-ready acceptance

Status: Open  
Bead: `haxe.ocaml-xgv.10`

Meaning in plain terms:

- All required gates and operational quality bars are green enough to claim practical replacement-readiness for targeted scope.

## Fast “where are we now?” commands

```bash
bd show haxe.ocaml-xgv.10
bd show haxe.ocaml-xgv.10.11
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

As we close remaining blockers (especially native RunCi progression), this document and `README.md` should be updated in the same change so non-experts can follow the journey.
