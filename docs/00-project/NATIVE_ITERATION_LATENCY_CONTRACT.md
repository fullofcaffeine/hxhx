# Native Iteration Latency Contract

Last audited: 2026-07-13

This document defines the project-level latency north star for native
`hxhx + reflaxe.ocaml` work. It is a measurement contract, not a claim that the
current implementation is already fast enough.

The user-facing goal is simple: common compiler and target-development loops
should get materially faster as `hxhx` and Reflaxe target promotion become
stage0-free and native by default, while strict Haxe `4.3.7` oracle gates remain
available for release proof.

The deeper product goal is Haxe-authored compiler performance: compiler and
backend logic should be pleasant to write in Haxe, then promotable through
`reflaxe.ocaml` into OCaml-backed native plugin, builtin, or bootstrap artifacts
whose runtime profile is in the same class as direct OCaml compiler code.
`hxhx` itself is Haxe-authored, not Reflaxe-authored; the relevant bet is that
`reflaxe.ocaml` can compile and bootstrap those Haxe sources into practical
native artifacts. In other words, `hxhx` may be created with Reflaxe as a
native compilation route, but the compiler core should stay ordinary Haxe
unless a separate architecture bead deliberately changes that boundary. Over
time, `hxhx`/Reflaxe-specific optimization should make
those promoted artifacts candidates for better-than-straightforward
hand-written performance when the compiler pipeline can specialize generated
code safely.

The accepted Oracle boundary for this distinction lives in
`docs/00-project/ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`.
It treats Reflaxe as a native artifact and backend/plugin seam for `hxhx`, not
as the default owner of compiler-core semantics.

## Why Current Loops Are Slow

Small compiler fixes can currently pay several costs that are only loosely
related to the code being changed:

- stage0-driven Haxe compilation of the compiler or bootstrap snapshots,
- Reflaxe output generation before native OCaml can be built,
- Dune/native linking for generated OCaml artifacts,
- broad repo guardrails such as provenance, generated-snapshot, and format
  checks,
- upstream-derived oracle gates that intentionally run larger compatibility
  suites.

Native `hxhx + reflaxe.ocaml` should reduce the repeated stage0/delegated part
of this loop. It will not eliminate every cost. Target-language compilers,
OCaml native linking, full upstream oracle suites, and report-only performance
lanes can still be the dominant work.

## Measurement Buckets

Measure these buckets separately:

- focused local smoke: the smallest target/backend or compiler smoke that proves
  the current edit,
- bootstrap snapshot regeneration: generated OCaml snapshot refresh and
  verification,
- stage0-free hxhx rebuild: rebuilding the native compiler from committed
  snapshots or current source without runtime stage0 delegation,
- native Reflaxe artifact loop: build a Reflaxe target/compiler into an
  OCaml-backed plugin or builtin artifact, then run a focused smoke,
- Full1 evidence gates: strict upstream-suite, macro/eval, plugin, and
  performance gates used for release claims.

Do not compare a focused smoke directly to Full1. They answer different
questions.

## Targets

The initial target is evidence discipline first, then speed. A release or public
performance claim must use measured medians from the relevant runner class.

<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_START -->
```json
{
  "schema": "native-iteration-latency-policy.v1",
  "contractMarker": "NATIVE_ITERATION_LATENCY_POLICY:PASS",
  "haxeCompatibilityBaseline": "4.3.7",
  "primaryOwnerBead": "haxe_ocaml-850ii",
  "completedFoundationBead": "haxe.ocaml-5rjl",
  "timingTool": "scripts/ci/full1-phase-timing.js",
  "policyGuard": "scripts/ci/native-iteration-latency-contract-check.js",
  "activeEvidenceLoop": {
    "reportSchema": "hxhx.kpi.v2",
    "reportValidator": "scripts/ci/hxhx-kpi-report-validator.js",
    "reportWorkflow": ".github/workflows/hxhx-kpi-report.yml",
    "artifactComparisonSchema": "hxhx.kpi-artifact-comparison.v1",
    "artifactComparisonValidator": "scripts/ci/hxhx-kpi-artifact-comparison.js",
    "artifactComparisonRunner": "scripts/hxhx/bench-kpi-artifact-comparison.sh"
  },
  "measurementBuckets": [
    {
      "id": "focused-local-smoke",
      "purpose": "Fast edit validation for a bounded compiler/backend change.",
      "target": "Median runtime should stay comfortably below the matching broad gate; warn if local p50 grows beyond 30s for a previously focused smoke.",
      "evidence": [
        "package.json",
        "scripts/ci/full1-phase-timing.js"
      ]
    },
    {
      "id": "bootstrap-snapshot-regeneration",
      "purpose": "Refresh committed OCaml bootstrap snapshots when repo-owned Haxe compiler sources change.",
      "target": "Native/stage0-free refresh should become materially faster than the stage0/delegated baseline before a 1.0 speed claim; until then, record medians and artifact footprint.",
      "evidence": [
        "scripts/hxhx/bench-bootstrap-regen.sh",
        "scripts/hxhx/profile-stage0-regen.sh",
        "docs/00-project/STAGE0_POLICY.md"
      ]
    },
    {
      "id": "stage0-free-hxhx-rebuild",
      "purpose": "Rebuild usable native hxhx artifacts without relying on upstream Haxe at runtime.",
      "target": "Track wall time and peak RSS separately from correctness; Full1 performance parity remains governed by FULL1_PERF_PARITY:PASS.",
      "evidence": [
        ".github/workflows/gate-perf-full1.yml",
        "docs/00-project/FULL1_PERF_PARITY_POLICY.md"
      ]
    },
    {
      "id": "native-reflaxe-artifact-loop",
      "purpose": "Build Haxe-authored compiler/backend code, such as a Reflaxe target or hxhx bootstrap artifact, as an OCaml-backed plugin or builtin artifact and run a focused smoke.",
      "target": "Native artifact iteration should beat the current delegated/stage0 promotion path for common compiler and target-development loops before it is recommended as the default path; where a direct OCaml compiler baseline exists, promoted Haxe-authored artifacts should be compared against that baseline and target the same performance class or better.",
      "evidence": [
        "scripts/hxhx/bench-native-reflaxe.sh",
        "docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md"
      ]
    },
    {
      "id": "full1-evidence-gates",
      "purpose": "Release proof for Haxe 4.3.7 compatibility, macro/eval parity, plugin parity, target parity, and performance parity.",
      "target": "Do not optimize by weakening coverage. Use phase timings to remove avoidable rebuild/setup duplication and to prevent hidden throughput regressions.",
      "evidence": [
        ".github/workflows/full1-suite-runners.yml",
        ".github/workflows/full1-eval-native.yml",
        ".github/workflows/gate3-full1-extended.yml",
        ".github/workflows/gate-perf-full1.yml",
        "docs/00-project/CI_GATES.md"
      ]
    }
  ]
}
```
<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_END -->

## What Should Get Faster

Expected improvement from native `hxhx + reflaxe.ocaml`:

- less stage0 handoff during compiler rebuild and snapshot refresh loops,
- less delegated Reflaxe setup when building stable Reflaxe targets as native
  plugin or builtin artifacts,
- faster focused target-development loops once target cores can be reused across
  plugin and builtin packaging,
- promoted compiler artifacts that can compete with direct OCaml compiler
  implementations on steady-state compiler workloads,
- less artifact churn from repeated bootstrap regeneration.

Expected to remain intentionally heavier:

- strict upstream Full1 suite gates,
- release-blocking performance parity evidence,
- target-language native builds and link steps,
- broad repo guardrails that protect provenance, generated artifacts, and
  release claims.

## Reporting Rule

The report workflow has an opt-in bytecode/native comparison. It runs both
compiler forms sequentially in one GitHub job and accepts the comparison only
when the commit, runner, CPU, toolchains, commands, repetition rules, and raw
metric rows match. A requested native build that falls back to bytecode is
reported as missing native evidence, not renamed to make the comparison pass.
The comparison remains diagnostic until repeated observations justify a
separate threshold decision.

When a bead materially changes compiler iteration speed, plugin/native artifact
loops, bootstrap regeneration, or Full1 throughput:

- record the measured command and runner context in the bead,
- update this contract or the referenced perf policy if the measurement bucket
  changes,
- update the README `Goals status` table only if production usability changes,
- otherwise record "README Goals progress bars unchanged" in the checkpoint.
