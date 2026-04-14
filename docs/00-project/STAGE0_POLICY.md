# Stage0 Policy (Runtime / Build / Maintenance)

This project keeps stage0 usage explicit and bounded.

- **stage0** means an upstream `haxe` compiler binary used as a bootstrap tool.
- **runtime path** means running `hxhx` as a compiler for user workloads.

The policy goal is simple:

- Runtime behavior should be stage0-free for native lanes.
- Stage0 is allowed only for explicit bootstrap maintenance tasks.

Full 1.0 performance parity uses the same boundary:

- measured Full 1.0 compiler performance evidence must compare stage0-free
  `hxhx` runtime lanes against upstream Haxe 4.3.7,
- stage0 bootstrap regeneration RSS/wall-time evidence is maintenance-only
  and cannot emit `FULL1_PERF_PARITY:PASS`,
- the canonical Full 1.0 performance policy is
  `docs/00-project/FULL1_PERF_PARITY_POLICY.md`.

## Bootstrap Stage0 Binary Selection (Regen Lane)

Bootstrap regeneration now records and enforces an explicit stage0-haxe selection policy:

- Script: `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`
- Default policy: `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native`

Policy modes:

- `warn`: keep resolved `HAXE_BIN` even if it is a wrapper.
- `prefer-native`: if resolved `HAXE_BIN` looks like a wrapper and a native candidate is detected, switch to native automatically.
- `require-native`: fail fast unless the resolved binary is native.

Native candidate detection order:

1. `HXHX_STAGE0_NATIVE_HAXE_BIN` (if executable)
2. `$(dirname "$HAXE_STD_PATH")/haxe` (if present/executable)
3. `$HOME/haxe/versions/<detected-version>/haxe` (if present/executable)

Each regen run prints deterministic selection markers:

- `Stage0 haxe requested`
- `Stage0 haxe policy`
- `Stage0 haxe resolved`
- `Stage0 haxe mode` (`native` or `wrapper`)
- optional `Stage0 native candidate`
- optional `Stage0 haxe policy action: switched wrapper to native candidate`

Quick non-emitting selection probe:

```bash
HAXE_BIN="$(which haxe)" \
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
  --stage0-selection-only \
  --report-json .tmp/stage0-selection-only.json
```

Machine-readable reports (`--report-json`) include:

- `status` (`ok` / `error`) and `exit_code`
- `haxe_bin_requested`
- `haxe_bin_resolved`
- `haxe_bin_mode`
- `haxe_bin_policy`
- `haxe_bin_switched`
- `haxe_native_candidate`
- `stage0_disable_prepasses` (`0` / `1`)
- `stage0_no_opt` (`0` / `1`)
- `stage0_no_inline` (`0` / `1`)
- `stage0_no_internal_tools` (`0` / `1`)
- `stage0_no_display` (`0` / `1`)
- `stage0_no_source_normalize_extract` (`0` / `1`)
- `stage0_no_native_decode_extract` (`0` / `1`)
- `stage0_no_parser_scan_extract` (`0` / `1`)
- `stage0_ocamlrunparam` (string; empty when unset)
- `stage0_observability.heartbeat_seconds`
- `stage0_observability.heartbeat_samples`
- `stage0_observability.heartbeat_peak_rss_mb`

Repro command pair (wrapper baseline vs native-preferred):

```bash
# Wrapper baseline (no auto-upgrade)
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=warn \
HAXE_BIN="$(which haxe)" \
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
  --incremental --no-verify --force \
  --report-json .tmp/stage0-wrapper-report.json

# Native-preferred (default policy)
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native \
HAXE_BIN="$(which haxe)" \
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
  --incremental --no-verify --force \
  --report-json .tmp/stage0-native-report.json
```

Benchmark harness (single command, policy A/B compare):

```bash
HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm \
HXHX_BOOTSTRAP_BENCH_REPS=1 \
HXHX_BOOTSTRAP_BENCH_VERIFY=0 \
HXHX_BOOTSTRAP_BENCH_DUNE_JOBS=auto,2,4 \
HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES=1 \
npm run hxhx:bench:bootstrap-regen
```

The benchmark writes `results.tsv` with per-run policy + peak RSS columns:

- `policy` (`wrapper` or `native`)
- `haxe_mode`
- `haxe_policy`
- `peak_rss_mb`

You can pass stage0 compile knobs through the benchmark:

- `HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT=1`
- `HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE=1`
- `HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES=1`
- `HXHX_BOOTSTRAP_BENCH_STAGE0_OCAMLRUNPARAM=s=4M`
- `HXHX_BOOTSTRAP_BENCH_DUNE_JOBS=auto,2,4` (runs worker-count matrix inside one benchmark run)

Selected defaults (worker + stage0 policy), with evidence:

- Keep `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native` as default.
- Keep `HXHX_DUNE_JOBS=auto` as default.
- Override with fixed workers (`HXHX_DUNE_JOBS=2` or `HXHX_DUNE_JOBS=4`) only when tuning a specific host/CI memory budget.
- Evidence table and run commands: `docs/benchmarks/STAGE0_BOOTSTRAP_THROUGHPUT_2026_03_05.md`.
- Stage0 memory knob comparison (no-opt/no-inline/disable-prepasses): `docs/benchmarks/STAGE0_MEMORY_KNOB_MATRIX_2026_03_05.md`.

## Stage0 Contributor Profiling (Regen Lane)

Use the profiling helper for reproducible contributor summaries:

```bash
# Fast failing profile sample (collects report + progress log + summary)
npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20

# Compare with lower-memory knob
npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-inline

# Try aggressive low-memory knobs together
npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-opt --no-inline

# Include OCaml GC tuning for stage0 haxe process
npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-opt --no-inline --ocamlrunparam s=4M
```

Artifacts are written to `.hxhx/profile/stage0-regen/<timestamp>/`:

- `regen_report.json` (policy/mode/peak RSS)
- `reflaxe_ocaml_progress.log` (telemetry stream)
- `progress_summary.json` (machine-readable class/checkpoint aggregate)
- `summary.txt` (report line + top class contributors + checkpoint lines; includes `peak_rss_source=report|stdout_fallback`)

You can summarize any existing progress log directly:

```bash
node scripts/hxhx/summarize-stage0-progress.js \
  --input /tmp/stage0-profile/reflaxe_ocaml_progress.log \
  --top 15 \
  --json-out /tmp/stage0-profile/progress_summary.json
```

You can compare multiple runs and rank stable hotspots (median by default):

```bash
node scripts/hxhx/compare-stage0-progress-summaries.js \
  --summary-dir /tmp/stage0-profile-run1 \
  --summary-dir /tmp/stage0-profile-run2 \
  --summary-dir /tmp/stage0-profile-run3 \
  --min-presence 2 \
  --sort median \
  --json-out /tmp/stage0-profile/compare_summary.json
```

For CI-style regression output (latest N runs, baseline vs latest deltas):

```bash
npm run hxhx:profile:stage0-hotspot-baseline -- \
  --root .hxhx/profile/stage0-regen \
  --samples 5 \
  --min-presence 2 \
  --sort median \
  --json-out .hxhx/profile/stage0-regen/compare.latest.json
```

For variance-safe memory A/B comparisons (baseline vs mitigation across repeated runs):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--disable-prepasses"
```

This writes `results.tsv` plus `summary.json`/`summary.txt` with median and average reduction percentages,
pair parity fields, and a recommendation classification (`promotable|profiling-only|rejected`).
Only runs with `peak_rss_mb > 0` are included in reduction math.

For parity-sensitive probes, require per-rep status parity (`status` or `status+exit`):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-stage3 --no-line-directives --no-external-macro-host --no-internal-tools" \
  --parity-mode status-exit \
  --require-status-parity
```

When parity is required and baseline/mitigation outcomes diverge, the runner exits `4`
with `parity_gate_status=fail` in `summary.txt`.

Additional mitigation candidate for source-level graph reduction:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--ocaml-only"
```

`--ocaml-only` maps to `HXHX_STAGE0_OCAML_ONLY=1` and adds
`-D hxhx_stage0_ocaml_only` during stage0 emit so linked `js-native` backend classes are excluded from that compile graph.

Additional parser-path mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-native-parser"
```

`--no-native-parser` maps to `HXHX_STAGE0_NO_NATIVE_PARSER=1` and adds
`-D hxhx_stage0_no_native_parser`, forcing the pure-Haxe parser branch even when
`-D hih_native_parser` is present in `build.hxml`.

Additional fallback-trimming mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-hx-parser"
```

`--no-hx-parser` maps to `HXHX_STAGE0_NO_HX_PARSER=1` and adds
`-D hxhx_stage0_no_hx_parser`, which trims pure-Haxe parser fallback paths from the stage0 compile graph.

Additional output-metadata mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-line-directives"
```

`--no-line-directives` maps to `HXHX_STAGE0_NO_LINE_DIRECTIVES=1` and adds
`-D ocaml_no_line_directives` during stage0 emit, trimming generated OCaml line-directive metadata.

Additional Stage3 expression-macro graph-trimming mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-expr-macros"
```

`--no-expr-macros` maps to `HXHX_STAGE0_NO_EXPR_MACROS=1` and adds
`-D hxhx_stage0_no_expr_macros`, which compiles out Stage3 expression-macro expansion paths in profiling runs.

Additional external-runtime-path mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-external-macro-host"
```

`--no-external-macro-host` maps to `HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST=1` and adds
`-D hxhx_stage0_no_external_macro_host`, which compiles out external macro-host runtime mode paths in profiling runs.

Additional Stage3-lane graph-trimming mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-stage3"
```

`--no-stage3` maps to `HXHX_STAGE0_NO_STAGE3=1` and adds
`-D hxhx_stage0_no_stage3`, which compiles out Stage3 native lane entrypoints in profiling runs.

Additional internal-tools graph-trimming mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-internal-tools"
```

`--no-internal-tools` maps to `HXHX_STAGE0_NO_INTERNAL_TOOLS=1` and adds
`-D hxhx_stage0_no_internal_tools`, which compiles out internal bring-up CLI paths (`--hxhx-stage1`, `--hxhx-parse`, `--hxhx-selftest`, `--hxhx-ocaml-interp`) in profiling runs.

This knob is profiling-only today; do not treat it as lane-equivalent for release snapshots until behavior parity is explicitly proven for maintained internal-tool workflows.

Internal-tool availability contract:

- Maintained source builds and release/dist builds must keep these internal workflows available:
  `--hxhx-stage1`, `--hxhx-parse`, `--hxhx-selftest`, `--hxhx-ocaml-interp`.
- `hxhx_stage0_no_internal_tools` is allowed only in profiling A/B runs and must not be enabled in committed bootstrap snapshots or release build lanes.

Additional display graph-trimming mitigation candidate:

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--no-display"
```

`--no-display` maps to `HXHX_STAGE0_NO_DISPLAY=1` and adds
`-D hxhx_stage0_no_display`, which compiles out Stage3 display response synthesis paths in profiling runs.

This knob is profiling-only today; do not treat it as lane-equivalent for release snapshots until display workflow parity is explicitly reviewed.

Additional parser-source graph candidate (inline baseline vs extracted helper):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --baseline-args "--no-source-normalize-extract" \
  --mitigation-args "" \
  --parity-mode status-exit
```

`--no-source-normalize-extract` maps to `HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT=1` and adds
`-D hxhx_stage0_no_source_normalize_extract`, which inlines HxParser source-normalization helpers back
into the parser module for A/B profiling. The default path keeps these helpers extracted.

Additional parser native-decode graph candidate (inline baseline vs extracted helper):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --baseline-args "--no-native-decode-extract" \
  --mitigation-args "" \
  --parity-mode status-exit
```

`--no-native-decode-extract` maps to `HXHX_STAGE0_NO_NATIVE_DECODE_EXTRACT=1` and adds
`-D hxhx_stage0_no_native_decode_extract`, which keeps native-protocol decode helpers in `ParserStage`
for A/B profiling. The default path delegates decode helpers to `ParserStageNativeDecode`.

Additional parser helper-scan graph candidate (inline baseline vs extracted helper):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --baseline-args "--no-parser-scan-extract" \
  --mitigation-args "" \
  --parity-mode status-exit
```

`--no-parser-scan-extract` maps to `HXHX_STAGE0_NO_PARSER_SCAN_EXTRACT=1` and adds
`-D hxhx_stage0_no_parser_scan_extract`, which keeps module-local helper scanners inline in `ParserStage`
for A/B profiling. The default path delegates scanner helpers to `ParserStageScanHelpers`.

Optional threshold gate (fails with exit code `3` when reduction is below target):

```bash
npm run hxhx:profile:stage0-regen-ab -- \
  --reps 3 \
  --failfast 120 \
  --mitigation-args "--disable-prepasses" \
  --min-reduction-pct 20 \
  --reduction-metric median
```

For GitHub Actions artifact-based baselines (recent runs + current summary):

```bash
npm run hxhx:profile:stage0-hotspot-gh-baseline -- \
  --workflow "Smoke / Stage0 Source Build" \
  --artifact-prefix stage0-source-smoke-profile \
  --samples 5 \
  --allow-partial \
  --current-summary /tmp/stage0_profile_regen/progress_summary.json
```

Current contributor pattern from 65s samples typically shows parser/typer-heavy classes near the top, for example:

- `HxParser`
- `ParserStage`
- `hxhx.ExprMacroExpander`
- `TyperStage`

## Policy table

| Lane | Allowed stage0 usage | Required guardrails | Typical commands |
| --- | --- | --- | --- |
| Runtime (native mode) | **Forbidden** for stage0 delegation paths | `HXHX_FORBID_STAGE0=1`; fail fast if delegation is attempted | `hxhx --ocaml ...`, `hxhx --js out.js ...` |
| Build | Allowed only when explicitly requested | `HXHX_FORCE_STAGE0=1` for source regeneration/builds; otherwise use committed bootstrap snapshots | `bash scripts/hxhx/build-hxhx.sh`, `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh` |
| Maintenance | Allowed for maintainer-only bootstrap refresh and diagnostics | Explicit maintainer scripts; never implicit in normal runtime/release lanes | `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`, `bash scripts/hxhx/regenerate-hxhx-macro-host-bootstrap.sh` |

Terminology note:

- `hxhx` still supports a Stage0 shim compatibility lane for bring-up/comparison workflows.
- The runtime policy above applies to **native runtime mode** when `HXHX_FORBID_STAGE0=1` is enabled (the release default).

## CI enforcement

CI enforces this policy in the stage0-free smoke lane:

- `bash scripts/hxhx/check-stage0-policy.sh release`
  - builds `hxhx` with `HXHX_FORBID_STAGE0=1` and an invalid `HAXE_BIN` sentinel,
  - proves runtime delegation is blocked and validates local stage0-free `--version` SemVer output,
  - proves native stage3 and macro-host selftest paths still work.

This keeps stage0 delegation failures explicit and reproducible.

## Release-path enforcement

`scripts/hxhx/build-dist.sh` defaults to strict stage0 policy:

- `HXHX_DIST_FORBID_STAGE0=1` (default) builds release artifacts with
  `HXHX_FORBID_STAGE0=1` and a non-existent `HAXE_BIN`.
- Any attempt to use a stage0 path in this mode fails fast.

If maintainers intentionally need a stage0-based dist experiment, they must opt out explicitly:

- `HXHX_DIST_FORBID_STAGE0=0 ...`

That opt-out is for debugging/maintenance only, not normal release policy.
