# CI Gates and Workflows

This page maps GitHub Actions workflow names to plain-English purpose and trigger scope.

For gate terminology (`Gate 1`, `Gate 2`, etc.), see `docs/00-project/GLOSSARY.md`.

## Trigger classes

- **PR required**: fast lanes expected to stay green for normal merges.
- **Nightly/scheduled**: heavier oracle/perf lanes that are too expensive for every PR.
- **Release**: strict release-readiness lanes used for publish confidence.
- **Manual**: maintainer-triggered diagnostics or targeted reruns.

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
| `Stdlib / Semantic Diff` | `.github/workflows/semantic-diff.yml` | Semantic diff smoke lane for portable behavior drift detection. | **PR required** (+scheduled/manual) | `push`, `pull_request`, weekly schedule, manual |

PR-required baseline is: **guardrails + core tests + scoped smokes** (`ci.yml`, gate-lite workflows, builtin smoke, JS oracle, stdlib tier1, semantic diff smoke).

## Scheduled compatibility and release gates (slow lanes)

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Gate 1 / Upstream Macro Unit Compatibility` | `.github/workflows/gate1.yml` | Full upstream unit macro compatibility baseline. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 2 / Upstream Macro Workloads` | `.github/workflows/gate2.yml` | Wider upstream `runci` macro workload checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 3 / Upstream Target Matrix` | `.github/workflows/gate3.yml` | Upstream target/workflow compatibility matrix checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate M7 / Replacement Bundle` | `.github/workflows/gate-m7.yml` | Replacement bundle lane used for strict release-readiness. | **Nightly/scheduled + Release** | weekly schedule, `release`, manual |
| `Stdlib Portable / Full` | `.github/workflows/stdlib-portable-full.yml` | Full portable stdlib conformance lane. | **Nightly/scheduled** | weekly schedule, manual |
| `Smoke / Stage0 Source Build` | `.github/workflows/stage0-source-smoke.yml` | Source-only stage0 smoke path integrity check. | **Nightly/scheduled** | daily schedule, manual |

`Gate M7` release/scheduled runs force strict settings:
- `HXHX_M7_PROFILE=full`
- `HXHX_M7_STRICT=1`
- `HXHX_FORBID_STAGE0=1`

Expected strict markers in logs:
- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

## Report-only / utility workflows

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Perf / HXHX KPI (Report Only)` | `.github/workflows/hxhx-kpi-report.yml` | KPI telemetry/report lane (non-blocking). | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Perf / M14 Portable vs Metal (Report Only)` | `.github/workflows/m14-perf-report.yml` | Portable vs metal benchmark reports (non-blocking). | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Pilot / Reflaxe.Elixir Todo Promotion` | `.github/workflows/reflaxe-elixir-pilot.yml` | Manual promotion pilot against external todo-app source checkout. | **Manual utility** | manual |
| `Utility / Bootstrap Regen Benchmark` | `.github/workflows/bootstrap-regen-bench.yml` | Harness benchmark runs for bootstrap regeneration speed. | **Manual utility** | manual |
| `Release / Semantic Publish` | `.github/workflows/release.yml` | Automated semantic release publication after CI success. | **Release automation** | workflow-run from CI, manual |
