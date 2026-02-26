# HXHX KPI Thresholds (Phase C6)

This document defines explicit KPI thresholds for the profile/plugin benchmark harness.

- Harness: `npm run hxhx:bench:kpi`
- Baseline report: `docs/benchmarks/HXHX_KPI_BASELINE.md`
- Machine-readable threshold file: `docs/benchmarks/kpi/hxhx-kpi-thresholds.v1.json`

## Methodology

1. Run the KPI harness with an explicit repetition count:

   ```bash
   HXHX_KPI_REPS=3 HXHX_KPI_RUN_MACRO_LANE=1 npm run hxhx:bench:kpi
   ```

2. Compare produced `report.json` medians against thresholds below.
3. If a threshold is exceeded, capture:
   - commit SHA
   - host/toolchain context
   - failing metric/lane values
   - whether the regression is expected (feature change) or unexpected.

## Threshold policy (explicit per KPI)

Current thresholds are intentionally conservative while we harden lanes across hosts.

| Metric | Lane | Max median |
| --- | --- | --- |
| `compile_wall_ms` | `ocaml_portable_builtin` | `140ms` |
| `compile_wall_ms` | `ocaml_metal_builtin` | `140ms` |
| `compile_wall_ms` | `upstream_haxe` | `140ms` |
| `compile_wall_ms` | `js_builtin` | `140ms` |
| `compile_wall_ms` | `js_provider` | `150ms` |
| `incremental_rebuild_ms` | `ocaml_portable_builtin` | `140ms` |
| `macro_baseline_compile_ms` | `ocaml_portable_builtin` | `160ms` |
| `macro_enabled_compile_ms` | `ocaml_portable_builtin` | `180ms` |
| `macro_overhead_ms` | `ocaml_portable_builtin` | `60ms` |
| `peak_rss_kb` | `ocaml_portable_builtin` | `70000kb` |
| `peak_rss_kb` | `ocaml_metal_builtin` | `70000kb` |
| `peak_rss_kb` | `upstream_haxe` | `70000kb` |
| `peak_rss_kb` | `js_builtin` | `70000kb` |
| `peak_rss_kb` | `js_provider` | `70000kb` |
| `macro_peak_rss_kb` | `ocaml_portable_builtin` | `75000kb` |

## Convergence budgets (report-only for now)

Portable remains the default OCaml contract. Performance work targets convergence to metal (and competitive upstream behavior) without changing portable semantics.

Median ratio targets emitted by `lane_ratios` in `report.json`:

| Ratio | Metric | Budget |
| --- | --- | --- |
| `portable_over_metal` | `compile_wall_ms` | `<= 1.15x` |
| `portable_over_metal` | `macro_enabled_compile_ms` | `<= 1.20x` |
| `portable_over_metal` | `peak_rss_kb` | `<= 1.25x` |
| `portable_over_upstream` | `compile_wall_ms` | `<= 1.30x` |
| `portable_over_upstream` | `macro_enabled_compile_ms` | `<= 1.40x` |
| `portable_over_upstream` | `peak_rss_kb` | `<= 1.50x` |
| `metal_over_upstream` | `compile_wall_ms` | `<= 1.20x` |
| `metal_over_upstream` | `peak_rss_kb` | `<= 1.40x` |

These are convergence targets, not merge-blocking thresholds yet.

## Next step

Once thresholds are stable across CI hosts, wire automatic threshold checks into a dedicated benchmark gate.
