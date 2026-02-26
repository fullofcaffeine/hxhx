# HXHX KPI Benchmarks — Profile/Plugin Baseline

This file records baseline numbers for the KPI harness introduced in `scripts/hxhx/bench-kpi.sh`.

- Command: `npm run hxhx:bench:kpi`
- Schema: `hxhx.kpi.v1` (`metrics` + `lane_ratios`)
- Raw machine-readable artifacts:
  - `docs/benchmarks/kpi/2026-02-24-macos-arm64-report.json`
  - `docs/benchmarks/kpi/2026-02-24-macos-arm64-samples.tsv`

## Baseline (macOS arm64)

Recorded: 2026-02-24  
Commit: `72a975d4ae4e48d344440888813eb18a0c8c3f34`  
OS: macOS 15.4 (arm64)  
Python: 3.14.2  
Haxe: 4.3.7  
Reps: 2  
Macro lane: enabled

### Median metrics

| Metric | Lane | Median |
| --- | --- | --- |
| `compile_wall_ms` | `ocaml_portable_builtin` | `91ms` |
| `compile_wall_ms` | `ocaml_metal_builtin` | `90ms` |
| `compile_wall_ms` | `upstream_haxe` | `TBD (next capture after upstream lane addition)` |
| `compile_wall_ms` | `js_builtin` | `88ms` |
| `compile_wall_ms` | `js_provider` | `87ms` |
| `incremental_rebuild_ms` | `ocaml_portable_builtin` | `87ms` |
| `macro_baseline_compile_ms` | `ocaml_portable_builtin` | `97ms` |
| `macro_enabled_compile_ms` | `ocaml_portable_builtin` | `103ms` |
| `macro_overhead_ms` | `ocaml_portable_builtin` | `5ms` |
| `peak_rss_kb` | `ocaml_portable_builtin` | `46416kb` |
| `peak_rss_kb` | `ocaml_metal_builtin` | `46312kb` |
| `peak_rss_kb` | `upstream_haxe` | `TBD (next capture after upstream lane addition)` |
| `peak_rss_kb` | `js_builtin` | `46416kb` |
| `peak_rss_kb` | `js_provider` | `46296kb` |
| `macro_peak_rss_kb` | `ocaml_portable_builtin` | `46712kb` |

### Convergence ratios (lane deltas)

`report.json` now emits median-based lane ratios under `lane_ratios`:

- `portable_over_metal`
- `portable_over_upstream`
- `metal_over_upstream`

Each ratio row carries metric-specific deltas for compile/macro/memory lanes when both source lanes exist.
These deltas are report-only today; enforcement remains a follow-up benchmark gate task.

## Regeneration

```bash
HXHX_KPI_REPS=2 HXHX_KPI_RUN_MACRO_LANE=1 npm run hxhx:bench:kpi
```

Override output path if needed:

```bash
HXHX_KPI_REPORT_DIR=.tmp/kpi-baseline npm run hxhx:bench:kpi
```
