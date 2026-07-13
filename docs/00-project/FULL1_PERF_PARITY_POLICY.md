# Full1 Performance Parity Policy

Last audited: 2026-07-13

This document defines the Full 1.0 performance policy for `hxhx` against
upstream Haxe 4.3.7.

Success markers:

- `FULL1_PERF_POLICY:PASS`: the policy surface is present, parseable, and wired
  into guardrails.
- `FULL1_PERF_PARITY:PASS`: measured stage0-free `hxhx` performance evidence
  satisfies this policy against upstream Haxe 4.3.7.

`FULL1_PERF_POLICY:PASS` is a contract marker only. It does not claim that
Full1 performance parity has been measured or achieved.

## Scope

Full1 performance parity compares the compiler runtime path:

- `hxhx` built from the committed bootstrap snapshots or equivalent
  stage0-free build artifacts.
- Native `hxhx` lanes run with stage0 delegation forbidden.
- Upstream Haxe pinned to `4.3.7`.

Stage0 bootstrap regeneration memory and wall time are maintenance evidence
only. They remain important for developer experience, but they cannot emit
`FULL1_PERF_PARITY:PASS` and they cannot substitute for stage0-free runtime
performance evidence.

## Metrics

The blocking evaluator must capture these metrics where the workload can expose
them deterministically:

- `compile_wall_ms`: elapsed compiler wall time per invocation. For workloads
  whose correctness runner performs downstream target emit/build/run steps, the
  measured command must isolate the compiler-bound lane and keep the
  end-to-end correctness marker as separate evidence.
- `incremental_rebuild_ms`: second-run compiler wall time after a warm build
  cache or unchanged input graph.
- `macro_overhead_ms`: compile-time overhead added by enabled macro callbacks.
- `peak_rss_kb`: maximum resident set size for the compiler process tree.

Wall-time metrics are primary because they are the user-visible replacement
criterion. RSS is blocking once the evaluator can collect it on the runner
platform without changing workload semantics.

## Thresholds

Full1 is an "hxhx is equal or better" claim:

- Required category median ratio: `hxhx / upstream_haxe <= 1.00`.
- Required workload hard ceiling: no required workload may exceed
  `hxhx / upstream_haxe > 1.10` after the noise retry policy.
- RSS hard ceiling: `hxhx / upstream_haxe <= 1.10` until RSS collection is
  stable across every release runner. After that, RSS should tighten to
  `<= 1.00` unless a documented target-specific memory tradeoff is accepted.
- Any exception blocks `FULL1_PERF_PARITY:PASS`; exceptions must be tracked as
  beads and reported as release blockers.

## Noise Model

The blocking evaluator must use:

- at least `5` measured repetitions per workload after warmup,
- at least `1` warmup run before measured repetitions,
- median aggregation for pass/fail ratios,
- coefficient-of-variation warning threshold of `15%`,
- near-zero delta metrics may ignore relative CV only when the `hxhx` median is
  both below the configured near-zero bound and no worse than upstream,
- one automatic retry for a workload whose first sample set is over threshold
  but also noisy,
- runner class pinned in the artifact metadata (`os`, `arch`, CPU model when
  available, OCaml version, Haxe version, `hxhx` commit).

If both attempts remain noisy, the workload is inconclusive and cannot emit
`FULL1_PERF_PARITY:PASS`.

## Workloads

Required workload references are deliberately existing commands so the policy
does not drift from runnable repo surfaces:

- KPI compile and macro overhead harness:
  - command: `npm run hxhx:bench:kpi`
  - source: `scripts/hxhx/bench-kpi.sh`
  - report-only workflow today: `.github/workflows/hxhx-kpi-report.yml`
  - blocking workflow: `.github/workflows/gate-perf-full1.yml`
  - Full1 evidence adapter: `scripts/ci/full1-kpi-evidence.js`
  - expected schema today: `hxhx.kpi.v2`
  - the report carries its own commit, clean-source flag, runner/CPU details,
    toolchain versions, hxhx artifact kind (for example OCaml bytecode versus a
    native executable), measurement method, and raw samples
- Native eval/interp latency probe:
  - command: `npm run test:full1:eval-native`
  - source: `scripts/ci/run-full1-eval-native.js`
  - Full1 evidence adapter: `scripts/ci/full1-eval-evidence.js`
  - measured compiler-latency source:
    `scripts/hxhx/run-upstream-unit-macro-stage3-no-emit.sh`
  - evidence scope: one strict native eval marker verification plus measured
    repetitions of the stage0-free Stage3 no-emit macro/typer path, so
    `compile_wall_ms` does not include OCaml target build/run time
  - required marker source: `FULL1_EVAL_NATIVE:PASS`
- Strict upstream suite compiler workloads:
  - command: `npm run test:full1:suites:strict`
  - source: `scripts/ci/run-upstream-suite.js`
  - Full1 evidence adapter: `scripts/ci/full1-suite-evidence.js`
  - evidence scope: measured repetitions of the stable `display` suite
    workload by default; the full strict suite matrix remains the separate
    correctness gate for `FULL1_SUITE_MATRIX:PASS`
  - required aggregate marker source: `FULL1_SUITE_MATRIX:PASS`

The future blocking evaluator may add larger project workloads, but it must not
remove these baseline references without updating this policy and guard.

## Artifact Contract

The blocking evaluator for `FULL1_PERF_PARITY:PASS` is:

- `scripts/ci/full1-perf-evaluator.js`

It must write a JSON summary
with:

- `schema`
- `marker`
- `haxeCompatibilityBaseline`
- `runner`
- `git`
- `workloads[]`
- `workloads[].samples[]`
- `workloads[].failures[]` for measured workload failures that must force a
  failing evaluation while still preserving artifacts and coverage diagnostics
- `workloads[].ratios`
- `thresholds`
- `noise`
- `decision`

`decision` must be `pass` before `FULL1_PERF_PARITY:PASS` is printed.
Synthetic evaluator fixtures are validated by:

- `scripts/ci/full1-perf-evaluator-fixture-test.js`
- `scripts/ci/full1-kpi-evidence-fixture-test.js`

The first raw workload adapter is:

- `scripts/ci/full1-kpi-evidence.js`
- `scripts/ci/hxhx-kpi-report-validator.js` validates the source report before
  it can become Full1 evidence

Additional Full1 evidence adapters are:

- `scripts/ci/full1-eval-evidence.js`
- `scripts/ci/full1-suite-evidence.js`

It converts the self-describing `hxhx.kpi.v2` report into
`full1-perf-evidence.v1`. Missing policy workloads or required metrics must
make `scripts/ci/full1-perf-evaluator.js` fail; partial evidence must never
emit `FULL1_PERF_PARITY:PASS`.

## Guard

The policy guard is:

- `scripts/ci/full1-perf-policy-check.js`

The guard parses the machine-readable policy block below and validates:

- baseline is `4.3.7`,
- policy and evidence markers are present,
- threshold and noise values are numeric and blocking,
- every required workload references an existing source file,
- every required workload command maps to an existing `package.json` script,
- report-only workflow references still exist.
- the release-blocking workflow and evidence adapters exist.

<!-- FULL1_PERF_POLICY_JSON_START -->
```json
{
  "schema": "full1-perf-policy.v1",
  "haxeCompatibilityBaseline": "4.3.7",
  "contractMarker": "FULL1_PERF_POLICY:PASS",
  "evidenceMarker": "FULL1_PERF_PARITY:PASS",
  "runtimeLane": "stage0-free hxhx",
  "releaseBlocking": true,
  "stage0MaintenanceOnly": true,
  "thresholds": {
    "requiredCategoryMedianMaxRatio": 1.0,
    "requiredWorkloadHardCeilingRatio": 1.1,
    "rssHardCeilingRatio": 1.1
  },
  "noise": {
    "warmupRuns": 1,
    "measuredRepetitions": 5,
    "aggregation": "median",
    "maxCoefficientOfVariationPct": 15,
    "nearZeroDeltaMetrics": [
      "macro_overhead_ms"
    ],
    "nearZeroDeltaMetricsMaxMedianMs": 5,
    "retryNoisyWorkloads": 1
  },
  "workloads": [
    {
      "id": "full1-kpi-compile-and-macro",
      "npmScript": "hxhx:bench:kpi",
      "source": "scripts/hxhx/bench-kpi.sh",
      "workflow": ".github/workflows/gate-perf-full1.yml",
      "reportOnlyWorkflow": ".github/workflows/hxhx-kpi-report.yml",
      "adapter": "scripts/ci/full1-kpi-evidence.js",
      "schema": "hxhx.kpi.v2",
      "requiredMetrics": [
        "compile_wall_ms",
        "incremental_rebuild_ms",
        "macro_overhead_ms",
        "peak_rss_kb"
      ]
    },
    {
      "id": "full1-native-eval-latency",
      "npmScript": "test:full1:eval-native",
      "source": "scripts/ci/run-full1-eval-native.js",
      "measuredSource": "scripts/hxhx/run-upstream-unit-macro-stage3-no-emit.sh",
      "adapter": "scripts/ci/full1-eval-evidence.js",
      "marker": "FULL1_EVAL_NATIVE:PASS",
      "requiredMetrics": [
        "compile_wall_ms"
      ]
    },
    {
      "id": "full1-upstream-suite-compiler-workloads",
      "npmScript": "test:full1:suites:strict",
      "source": "scripts/ci/run-upstream-suite.js",
      "adapter": "scripts/ci/full1-suite-evidence.js",
      "marker": "FULL1_SUITE_MATRIX:PASS",
      "requiredMetrics": [
        "compile_wall_ms",
        "peak_rss_kb"
      ]
    }
  ]
}
```
<!-- FULL1_PERF_POLICY_JSON_END -->
