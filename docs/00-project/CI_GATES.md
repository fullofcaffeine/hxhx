# CI Gates and Workflows

This page maps GitHub Actions workflow names to plain-English purpose and trigger scope.

For gate terminology (`Gate 1`, `Gate 2`, etc.), see `docs/00-project/GLOSSARY.md`.

## Required on PR/push (fast lanes)

| Workflow | File | Purpose | Triggers |
| --- | --- | --- | --- |
| `CI / Core PR Checks` | `.github/workflows/ci.yml` | Core guardrails, tests, and smoke lanes that must stay green on normal changes. | `push`, `pull_request` |
| `Security / CodeQL` | `.github/workflows/codeql.yml` | Static security analysis for JS/TS surfaces. | `push`, `pull_request`, weekly schedule |
| `Gate 1 Lite / Upstream Macro Unit Smoke` | `.github/workflows/gate1-lite.yml` | Fast upstream unit macro compatibility smoke. | `push`, `pull_request` |
| `Gate 2 Lite / Workloads Smoke` | `.github/workflows/gate2-lite.yml` | Fast workload/macro compatibility smoke. | `push`, `pull_request` |
| `Gate 3 Builtin / Native Target Smoke` | `.github/workflows/gate3-builtin.yml` | Native builtin target smoke (`ocaml` and `js`) plus JS oracle smoke lane. | `push`, `pull_request`, weekly schedule, manual |
| `Oracle / JS Smoke (Upstream vs HXHX)` | `.github/workflows/js-oracle-smoke.yml` | Focused JS behavior comparison against upstream oracle. | `push`, `pull_request`, manual |
| `Stdlib Portable / Tier1` | `.github/workflows/stdlib-portable-lite.yml` | Tier1 portable stdlib conformance checks. | `push`, `pull_request` |
| `Stdlib / Semantic Diff` | `.github/workflows/semantic-diff.yml` | Semantic diff smoke lane for portable behavior drift detection. | `push`, `pull_request`, weekly schedule, manual |

## Scheduled compatibility and release gates (slow lanes)

| Workflow | File | Purpose | Triggers |
| --- | --- | --- | --- |
| `Gate 1 / Upstream Macro Unit Compatibility` | `.github/workflows/gate1.yml` | Full upstream unit macro compatibility baseline. | weekly schedule, manual |
| `Gate 2 / Upstream Macro Workloads` | `.github/workflows/gate2.yml` | Wider upstream `runci` macro workload checks. | weekly schedule, manual |
| `Gate 3 / Upstream Target Matrix` | `.github/workflows/gate3.yml` | Upstream target/workflow compatibility matrix checks. | weekly schedule, manual |
| `Gate M7 / Replacement Bundle` | `.github/workflows/gate-m7.yml` | Scoped replacement bundle (strict/full lanes for release-readiness). | weekly schedule, `release`, manual |
| `Stdlib Portable / Full` | `.github/workflows/stdlib-portable-full.yml` | Full portable stdlib conformance lane. | weekly schedule, manual |
| `Smoke / Stage0 Source Build` | `.github/workflows/stage0-source-smoke.yml` | Source-only stage0 smoke path integrity check. | daily schedule, manual |

## Report-only / utility workflows

| Workflow | File | Purpose | Triggers |
| --- | --- | --- | --- |
| `Perf / HXHX KPI (Report Only)` | `.github/workflows/hxhx-kpi-report.yml` | KPI telemetry/report lane (non-blocking). | `push`, `pull_request`, manual |
| `Perf / M14 Portable vs Metal (Report Only)` | `.github/workflows/m14-perf-report.yml` | Portable vs metal benchmark reports (non-blocking). | `push`, `pull_request`, manual |
| `Utility / Bootstrap Regen Benchmark` | `.github/workflows/bootstrap-regen-bench.yml` | Manual harness benchmark runs for bootstrap regeneration speed. | manual |
| `Release / Semantic Publish` | `.github/workflows/release.yml` | Automated semantic release publication. | workflow-run from CI, manual |
