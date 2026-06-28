# CI Gates and Workflows

This page maps GitHub Actions workflow names to plain-English purpose and trigger scope.

For gate terminology (`Gate 1`, `Gate 2`, etc.), see `docs/00-project/GLOSSARY.md`.
For lane/profile context, use the canonical beginner truth table:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- Scoped 1.0 parity contract map (current lanes):
  `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- Full 1.0 parity contract map (strict closure track):
  `docs/00-project/PARITY_MAP_FULL_1_0.md`
- Macro runtime parity blocker list (explicit gaps before inproc-default):
  `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`
- Weekly ops audit procedure (scheduled gates + triage):
  `docs/00-project/WEEKLY_CI_EVIDENCE.md`
- Full vs scoped release contract:
  `docs/00-project/FULL_1_0_CONTRACT.md`
- Public `Scoped 1.0` vs `Full 1.0` claim checklist:
  `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

## Gate purpose by lane (quick map)

| Gate | Primary purpose in lane terms |
| --- | --- |
| Gate 0 | Fast safety checks across delegated/native lanes before merge |
| Gate 1 | Upstream macro/unit compatibility baseline (oracle lane confidence) |
| Gate 2 | Wider upstream macro/workload compatibility checks |
| Gate 3 | Native target/workflow compatibility scope checks (`--ocaml`, `--js <file>`) |
| Gate 4 | Distribution, plugin, and performance readiness checks |

## Trigger classes

- **PR required**: fast lanes expected to stay green for normal merges.
- **Nightly/scheduled**: heavier oracle/perf lanes that are too expensive for every PR.
- **Release**: strict release-readiness lanes used for publish confidence.
- **Manual**: maintainer-triggered diagnostics or targeted reruns.

## Interpreting GitHub UI State

`PR required` is the repository merge-policy classification for this project. It is the set of workflows maintainers should treat as blocking for ordinary merges, even when a checkout, fork, or private repository instance does not currently enforce GitHub branch-protection rules.

When GitHub branch protection is enabled, it should require the PR-required fast lanes listed below. When branch protection is disabled, the docs remain the source of truth for the intended baseline, and maintainers must verify these workflows manually before merging release-relevant work.

Cancelled runs on older commits are not baseline failures when they were superseded by a newer push under the same concurrency group. Evaluate the latest run for the current head SHA. A skipped `Release / Semantic Publish` workflow-run after a non-successful or superseded `CI / Core PR Checks` run is also expected and does not count as a release-lane failure by itself.

## Release policy (Scoped 1.0)

- `Release / Semantic Publish` (`.github/workflows/release.yml`) is the automation lane for normal semantic releases.
- `Gate M7 / Replacement Bundle` (`.github/workflows/gate-m7.yml`) is the strict replacement-readiness lane.
- For current 0.x automation, M7 strict is **not** a hard precondition of semantic publish.
- For Scoped 1.0 release readiness/sign-off, M7 strict **is required** and must show:
  - `M7_STRICT_STAGE0:PASS`
  - `M7_REPLACEMENT_READY:PASS`

For Full 1.0 claims, use the strict Full contract and markers in:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

For strict `Full 1.0` / `Haxe 4.3.7-equivalent` claims, the primary proof is the relevant upstream Haxe 4.3.7 suite matrix running under `hxhx`.
Repo-local focused regressions and bridge tests are supporting evidence for diagnosis and closure work; they do not replace upstream-suite proof.

## PR-required fast lanes

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `CI / Core PR Checks` | `.github/workflows/ci.yml` | Core guardrails, tests, and scoped smokes for baseline safety. | **PR required** | `push`, `pull_request` |
| `Security / CodeQL` | `.github/workflows/codeql.yml` | Static security analysis for JS/TS surfaces. | **PR required** (+scheduled) | `push`, `pull_request`, weekly schedule |
| `Gate 1 Lite / Upstream Macro Unit Smoke` | `.github/workflows/gate1-lite.yml` | Fast upstream unit macro compatibility smoke. | **PR required** | `push`, `pull_request` |
| `Gate 2 Lite / Workloads Smoke` | `.github/workflows/gate2-lite.yml` | Fast workload/macro compatibility smoke. | **PR required** | `push`, `pull_request` |
| `Gate 3 Builtin / Native Target Smoke` | `.github/workflows/gate3-builtin.yml` | Native builtin target smoke (`ocaml` and `js`) plus JS oracle smoke lane. | **PR required** (+scheduled/manual) | `push`, `pull_request`, weekly schedule, manual |
| `Oracle / JS Smoke (Upstream vs HXHX)` | `.github/workflows/js-oracle-smoke.yml` | Focused JS behavior comparison against upstream oracle. | **PR required** (+manual) | `push`, `pull_request`, manual |
| `Stdlib Portable / Tier1` | `.github/workflows/stdlib-portable-lite.yml` | Tier1 portable stdlib conformance checks. | **PR required** | `push`, `pull_request` |
| `Stdlib / Semantic Diff` | `.github/workflows/semantic-diff.yml` | Scoped semantic-diff-lite canary for stdlib/runtimegen-sensitive PRs, plus nightly expanded lane. | **PR required** (+scheduled/manual) | `push`, `pull_request`, weekly schedule, manual |

PR-required baseline is: **guardrails + core tests + scoped smokes** (`ci.yml`, gate-lite workflows, builtin smoke, JS oracle, stdlib tier1, semantic diff smoke).

Stable success markers used by required lanes:

- `STAGE0_FREE_SMOKE:PASS` (`ci.yml` job `stage0-free-smoke`)
- `JS_NATIVE_SMOKE:PASS` (`ci.yml` job `js-native-smoke`)
- `PLUGIN_MATRIX_STRICT:PASS` (`ci.yml` job `plugin-matrix`)
- `GATE1_LITE:PASS` (`gate1-lite.yml`)
- `GATE2_LITE:PASS` (`gate2-lite.yml`)
- `SEMANTIC_DIFF_LITE_SCOPE:RUN` or `SEMANTIC_DIFF_LITE_SCOPE:SKIP_NO_RELEVANT_CHANGES` (`semantic-diff.yml` job `Semantic diff (PR smoke)`)
- `SEMANTIC_DIFF_LITE:PASS` (emitted when scoped semantic-diff lane executes)

Semantic-diff PR artifacts are uploaded as `semantic-diff-pr-artifacts` and include:

- `changed_files.txt` (revision file list)
- `matched_files.txt` (scoped trigger matches)
- `semantic_diff_lite.marker.txt` (scope + pass/skip markers)
- lane reports under `.artifacts/semantic-diff/pr/**` when the scoped lane runs

## Scheduled compatibility and release gates (slow lanes)

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Gate 1 / Upstream Macro Unit Compatibility` | `.github/workflows/gate1.yml` | Full upstream unit macro compatibility baseline. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 2 / Upstream Macro Workloads` | `.github/workflows/gate2.yml` | Wider upstream `runci` macro workload checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Macro Runtime Parity (Weekly)` | `.github/workflows/macro-runtime-parity-weekly.yml` | Runs upstream macro + display checks in both macro runtime modes (`external-host`, `inproc`) with mode-tagged artifacts, phase timings, reusable outputs, and aggregate macro parity markers. | **Nightly/scheduled + Release + Reusable** | weekly schedule, manual, `release`, `workflow_call` |
| `Full1 / Eval Native` | `.github/workflows/full1-eval-native.yml` | Runs the upstream-aligned native eval/interp baseline (`tests/unit/compile-macro.hxml`) in strict stage0-forbidden mode and emits a structured eval marker/artifact. | **Release + Manual + Reusable** | manual, `release`, `workflow_call` |
| `Gate 3 / Upstream Target Matrix` | `.github/workflows/gate3.yml` | Upstream target/workflow compatibility matrix checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 3 Full1 / Extended Targets Strict` | `.github/workflows/gate3-full1-extended.yml` | Full1 strict extended target matrix (`Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php`) with no-skip enforcement, controlled inner timeout, JSON summary, and phase-timing artifacts. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Suite Runners Strict` | `.github/workflows/full1-suite-runners.yml` | Full1 strict suite runners for `misc`, `server`, `threads`, `optimization`, `display` with per-suite log, summary, and phase-timing artifacts. Inproc suites (`misc`, `threads`, `display`) do not download or export a macro host; current external-host suites (`server`, `optimization`) consume the shared macro-host artifact until inproc parity catches up. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Source-Build Probe` | `.github/workflows/full1-source-probe.yml` | Non-blocking diagnostic lane: force source build (`HXHX_FORCE_STAGE0=1`) and run narrowed strict suites (`server`, `optimization`) to detect bootstrap-lagged fixes without destabilizing the primary matrix. Summary JSON stays compact; child processes are hard-timeboxed and full logs are separate artifacts. | **Nightly/scheduled diagnostic** | weekly schedule, manual |
| `Full1 / Bootstrap-Source Reconciliation` | `.github/workflows/full1-bootstrap-source-reconcile.yml` | Diagnostic evidence lane that runs `server` + `optimization` in both bootstrap-built and source-built lanes on the same commit, then classifies each blocker as bootstrap lag vs source-build instability vs real parity bug. | **Nightly/scheduled diagnostic** | weekly schedule, manual |
| `Gate Perf Full1 / HXHX vs Haxe` | `.github/workflows/gate-perf-full1.yml` | Release-blocking Full1 performance parity lane. Uploads raw KPI evidence, phase timings, and evaluated Full1 perf summary, then emits `FULL1_PERF_PARITY:PASS` only through the evaluator after the policy passes. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Full1 / Plugin Parity` | `.github/workflows/full1-plugin-parity.yml` | Runs the three required `reflaxe.ocaml` plugin proof rows, uploads per-proof artifacts with phase timings, and emits `FULL1_PLUGIN_PARITY:PASS` only when all proof rows pass. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Gate Full1 / Strict Matrix + Macro Eval + Plugin Parity` | `.github/workflows/gate-full1.yml` | Full1 aggregate gate that composes strict suite runners, strict extended Gate3, reusable macro runtime parity, reusable native eval, and reusable plugin parity. It emits `FULL1_SUITE_MATRIX:PASS` for strict matrix success, `FULL1_MACRO_EVAL_PARITY:PASS` for macro+eval closure, and `FULL1_PLUGIN_PARITY:PASS` for plugin closure. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Gate Full1 RC / Release Go-No-Go` | `.github/workflows/gate-full1-rc.yml` | Full1 public-claim release gate that composes Gate Full1, Gate Perf Full1, and local contract guards through `scripts/ci/full1-rc-gate.js`. It uploads RC summary JSON and emits `FULL1_RELEASE_GO:PASS` only when every required Full1 scope marker is present. | **Release + Manual** | `release`, manual |
| `Gate M7 / Replacement Bundle` | `.github/workflows/gate-m7.yml` | Strict replacement-readiness lane (scheduled/manual + release-event verification). | **Nightly/scheduled + Release** | weekly schedule, `release`, manual |
| `Stdlib Portable / Full` | `.github/workflows/stdlib-portable-full.yml` | Full portable stdlib conformance lane. | **Nightly/scheduled** | weekly schedule, manual |
| `Smoke / Stage0 Source Build` | `.github/workflows/stage0-source-smoke.yml` | Source-only stage0 smoke path integrity check. | **Nightly/scheduled** | daily schedule, manual |

Heavy Full1 workflows use event+ref scoped concurrency and cancel stale in-progress reruns so manual retries and scheduled evidence runs do not pile up behind obsolete work.

Heavy Full1 OCaml/dune worker and cache policy:
- Full1 workflows that build `hxhx`, macro host artifacts, or plugin/eval proof binaries keep `HXHX_DUNE_JOBS=auto` explicit.
- Fixed worker caps such as `HXHX_DUNE_JOBS=2` or `HXHX_DUNE_JOBS=4` are allowed only for a workflow-specific memory/throughput experiment with fresh evidence.
- Current benchmark source: `docs/benchmarks/STAGE0_BOOTSTRAP_THROUGHPUT_2026_03_05.md`.
  In that bounded matrix, fixed worker settings increased peak RSS compared with `auto`, so `auto` remains the default.
- Workflows that already require `ocaml/setup-ocaml` for opam-backed proof setup keep `dune-cache: true`; apt-based Full1 lanes should not be converted to opam/setup-ocaml without comparable timing/RSS evidence.

Full1 suite runner timing artifacts:
- build jobs emit `build_hxhx.timings.*` and `build_macro_host.timings.*`
- suite jobs emit `<suite>.timings.jsonl`, `<suite>.timings.summary.json`, and `<suite>.timings.md`
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for quick before/after review

Full1 perf timing artifacts:
- raw artifacts include `full1-perf.timings.jsonl`
- evaluated artifacts include `full1-perf.timings.summary.json` and `full1-perf.timings.md`
- measured phases are `build_hxhx_binary`, `build_macro_host_binary`, `kpi_benchmark`, `eval_evidence`, `suite_evidence`, and `perf_evaluator`

Full1 native eval timing artifacts:
- raw artifacts include `full1-eval-native.timings.jsonl`
- evaluated artifacts include `full1-eval-native.timings.summary.json` and `full1-eval-native.timings.md`
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, `build_hxhx_binary`, and `native_eval_runner`

Full1 plugin parity timing artifacts:
- proof artifacts include `<proof-id>.timings.jsonl`, `<proof-id>.timings.summary.json`, and `<proof-id>.timings.md`
- measured phases include OCaml package prep, npm/Haxe dependency prep, optional upstream eval-host preparation, and `plugin_proof`
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for each proof row

Macro runtime parity timing artifacts:
- mode-tagged artifacts include `<mode>.timings.jsonl`, `<mode>.timings.summary.json`, and `<mode>.timings.md`
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, `build_hxhx_binary`, unit macro, runci macro, and display/protocol checks
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for each runtime mode

Full1 Gate3 extended timing artifacts:
- raw artifacts include `gate3-full1-extended.timings.jsonl`
- evaluated artifacts include `gate3-full1-extended.timings.summary.json` and `gate3-full1-extended.timings.md`
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, and `strict_extended_gate3_matrix`
- `strict_extended_gate3_matrix` is wrapped in an inner timeout below the job timeout so overruns fail with uploaded artifacts instead of GitHub job cancellation being mistaken for a successful matrix phase.

Native iteration latency contract:
- `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md` defines the project-level buckets for focused local smokes, bootstrap regeneration, stage0-free `hxhx` rebuilds, native Reflaxe artifact loops, and Full1 gates.
- `scripts/ci/native-iteration-latency-contract-check.js` validates that the contract stays connected to existing timing/reporting surfaces.
- The contract marker is `NATIVE_ITERATION_LATENCY_POLICY:PASS`; it is a policy/coverage marker only, not measured speed evidence.

Diagnostic Full1 timing scope:
- `.github/workflows/full1-source-probe.yml` and `.github/workflows/full1-bootstrap-source-reconcile.yml` are intentionally outside the mandatory per-phase timing-artifact contract while they remain non-blocking diagnostic lanes.
- Their purpose is source-vs-bootstrap failure classification, not release throughput regression detection. They already publish compact JSON summaries with run duration, build/suite timeout status, and pass/warn classification data.
- Do not treat missing `*.timings.jsonl`, `*.timings.summary.json`, or `*.timings.md` artifacts from these diagnostic workflows as a coverage gap.
- If either diagnostic workflow is promoted to a release-blocking or reusable Full1 gate, add the same phase-timing artifact contract used by the heavy Full1 lanes before making it blocking.

`Gate M7` release/scheduled runs force strict settings:
- `HXHX_M7_PROFILE=full`
- `HXHX_M7_STRICT=1`
- `HXHX_FORBID_STAGE0=1`

Expected strict markers in logs:
- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

Macro runtime mode policy (native lanes):
- default mode is `inproc`
- fallback/debug mode is `external-host`
- rollback knobs:
  - env: `HXHX_MACRO_RUNTIME_MODE=external-host`
  - flag: `--hxhx-macro-runtime external-host`
- audit marker: `hxhx_macro_runtime_mode=<mode>`

Macro runtime parity weekly markers:
- `MACRO_RUNTIME_PARITY_UNIT_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_UNIT_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_RUNCI_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_RUNCI_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_WEEKLY:PASS`
- `FULL1_MACRO_PARITY:PASS`

Full1 extended Gate3 marker:

- `FULL1_GATE3_EXTENDED_TARGETS:PASS` (`.github/workflows/gate3-full1-extended.yml`)

Full1 strict suite runner markers:

- `FULL1_SUITE_MISC:PASS`
- `FULL1_SUITE_SERVER:PASS`
- `FULL1_SUITE_THREADS:PASS`
- `FULL1_SUITE_OPTIMIZATION:PASS`
- `FULL1_SUITE_DISPLAY:PASS`

Full1 aggregate matrix marker:

- `FULL1_SUITE_MATRIX:PASS` (`.github/workflows/gate-full1.yml`)

Full1 native eval marker:

- `FULL1_EVAL_NATIVE:PASS` (`.github/workflows/full1-eval-native.yml`)

Full1 macro/eval aggregate marker:

- `FULL1_MACRO_EVAL_PARITY:PASS` (`.github/workflows/gate-full1.yml`)

Full1 plugin parity marker:

- `FULL1_PLUGIN_PARITY:PASS` (`.github/workflows/full1-plugin-parity.yml` and `.github/workflows/gate-full1.yml`)

Full1 flake policy marker:

- `FULL1_FLAKE_POLICY:PASS` (planned by `haxe.ocaml-f1cl.3.4`; RC release
  gate will not emit `FULL1_RELEASE_GO:PASS` until this marker is supplied)

Full1 performance policy marker:

- `FULL1_PERF_POLICY:PASS` (`scripts/ci/full1-perf-policy-check.js`)

Full1 measured performance parity marker:

- `FULL1_PERF_PARITY:PASS` (`.github/workflows/gate-perf-full1.yml`;
  evaluator: `scripts/ci/full1-perf-evaluator.js`; policy source:
  `docs/00-project/FULL1_PERF_PARITY_POLICY.md`)

Full1 release go/no-go marker:

- `FULL1_RELEASE_GO:PASS` (`.github/workflows/gate-full1-rc.yml`;
  evaluator: `scripts/ci/full1-rc-gate.js`; scope source:
  `docs/02-user-guide/compat/full-1.0-scope.json`)

Gate Full1 also requires green reusable jobs from:

- `.github/workflows/macro-runtime-parity-weekly.yml`
- `.github/workflows/full1-eval-native.yml`

Full1 source-build probe marker (non-blocking diagnostic lane):

- `FULL1_SOURCE_BUILD_PROBE:PASS` or `FULL1_SOURCE_BUILD_PROBE:WARN` (`.github/workflows/full1-source-probe.yml`)

Full1 bootstrap-source reconciliation marker (diagnostic classification lane):

- `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:PASS` or `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN` (`.github/workflows/full1-bootstrap-source-reconcile.yml`)

Local suite runner guide for Full1 suite scaffolding (`misc/server/threads/optimization/display`):

- `docs/01-getting-started/RUN_FULL1_SUITES_LOCALLY.md`

## Report-only / utility workflows

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Perf / HXHX KPI (Report Only)` | `.github/workflows/hxhx-kpi-report.yml` | KPI telemetry/report lane (non-blocking). | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Perf / M14 Portable vs Metal (Report Only)` | `.github/workflows/m14-perf-report.yml` | Portable vs metal benchmark reports (non-blocking). | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Pilot / Reflaxe.Elixir Todo Promotion` | `.github/workflows/reflaxe-elixir-pilot.yml` | Scheduled/manual promotion pilot against pinned external todo-app source checkout, uploading promotion/load evidence. | **Manual + scheduled diagnostic** | weekly + manual |
| `Utility / Bootstrap Regen Benchmark` | `.github/workflows/bootstrap-regen-bench.yml` | Harness benchmark runs for bootstrap regeneration speed. | **Manual utility** | manual |
| `Release / Semantic Publish` | `.github/workflows/release.yml` | Automated semantic release publication after CI success. | **Release automation** | workflow-run from CI, manual |
