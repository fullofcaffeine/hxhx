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
| `Macro Runtime Parity (Weekly)` | `.github/workflows/macro-runtime-parity-weekly.yml` | Runs upstream macro + display checks in both macro runtime modes (`external-host`, `inproc`) with mode-tagged artifacts, reusable outputs, and aggregate macro parity markers. | **Nightly/scheduled + Release + Reusable** | weekly schedule, manual, `release`, `workflow_call` |
| `Full1 / Eval Native` | `.github/workflows/full1-eval-native.yml` | Runs the upstream-aligned native eval/interp baseline (`tests/unit/compile-macro.hxml`) in strict stage0-forbidden mode and emits a structured eval marker/artifact. | **Release + Manual + Reusable** | manual, `release`, `workflow_call` |
| `Gate 3 / Upstream Target Matrix` | `.github/workflows/gate3.yml` | Upstream target/workflow compatibility matrix checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 3 Full1 / Extended Targets Strict` | `.github/workflows/gate3-full1-extended.yml` | Full1 strict extended target matrix (`Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php`) with no-skip enforcement and JSON summary artifacts. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Suite Runners Strict` | `.github/workflows/full1-suite-runners.yml` | Full1 strict suite runners for `misc`, `server`, `threads`, `optimization`, `display` with per-suite log + summary artifacts. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Source-Build Probe` | `.github/workflows/full1-source-probe.yml` | Non-blocking diagnostic lane: force source build (`HXHX_FORCE_STAGE0=1`) and run narrowed strict suites (`server`, `optimization`) to detect bootstrap-lagged fixes without destabilizing the primary matrix. | **Nightly/scheduled diagnostic** | weekly schedule, manual |
| `Full1 / Bootstrap-Source Reconciliation` | `.github/workflows/full1-bootstrap-source-reconcile.yml` | Diagnostic evidence lane that runs `server` + `optimization` in both bootstrap-built and source-built lanes on the same commit, then classifies each blocker as bootstrap lag vs source-build instability vs real parity bug. | **Nightly/scheduled diagnostic** | weekly schedule, manual |

Heavy Full1 workflows use event+ref scoped concurrency and cancel stale in-progress reruns so manual retries and scheduled evidence runs do not pile up behind obsolete work.
| `Gate Full1 / Strict Matrix + Macro Eval Parity` | `.github/workflows/gate-full1.yml` | Full1 aggregate gate that composes strict suite runners, strict extended Gate3, reusable macro runtime parity, and reusable native eval. It emits `FULL1_SUITE_MATRIX:PASS` for strict matrix success and `FULL1_MACRO_EVAL_PARITY:PASS` for macro+eval closure. | **Nightly/scheduled + Release** | weekly schedule, `release`, manual |
| `Gate M7 / Replacement Bundle` | `.github/workflows/gate-m7.yml` | Strict replacement-readiness lane (scheduled/manual + release-event verification). | **Nightly/scheduled + Release** | weekly schedule, `release`, manual |
| `Stdlib Portable / Full` | `.github/workflows/stdlib-portable-full.yml` | Full portable stdlib conformance lane. | **Nightly/scheduled** | weekly schedule, manual |
| `Smoke / Stage0 Source Build` | `.github/workflows/stage0-source-smoke.yml` | Source-only stage0 smoke path integrity check. | **Nightly/scheduled** | daily schedule, manual |

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
| `Pilot / Reflaxe.Elixir Todo Promotion` | `.github/workflows/reflaxe-elixir-pilot.yml` | Manual promotion pilot against external todo-app source checkout. | **Manual utility** | manual |
| `Utility / Bootstrap Regen Benchmark` | `.github/workflows/bootstrap-regen-bench.yml` | Harness benchmark runs for bootstrap regeneration speed. | **Manual utility** | manual |
| `Release / Semantic Publish` | `.github/workflows/release.yml` | Automated semantic release publication after CI success. | **Release automation** | workflow-run from CI, manual |
