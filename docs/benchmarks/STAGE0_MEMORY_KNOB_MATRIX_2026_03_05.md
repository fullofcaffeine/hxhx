# Stage0 Memory Knob Matrix (2026-03-05)

This artifact tracks native-stage0 memory probe deltas for `haxe.ocaml-a0pt.1`.

## Probe setup

- Stage0 policy: `prefer-native`
- Stage0 binary request: wrapper path from `which haxe` (policy resolves to native)
- Probe mode: bounded failfast runs (intentionally `status=error`)
- Scenario args: `--incremental --no-verify --force`

Raw tabular data:
- `docs/benchmarks/stage0-memory-knob-matrix-2026-03-05.tsv`

## Results summary

Failfast `90s` family:
- Baseline: `8713MB`
- `HXHX_STAGE0_DISABLE_PREPASSES=1`: `7011MB` (`-19.53%`)
- `HXHX_STAGE0_NO_INLINE=1`: `8628MB` (`-0.98%`)
- `HXHX_STAGE0_NO_INLINE=1` + `HXHX_STAGE0_DISABLE_PREPASSES=1`: `7308MB` (`-16.13%`)
- `HXHX_STAGE0_NO_OPT=1`: `7079MB` (`-18.75%`)
- `HXHX_STAGE0_NO_OPT=1` + `HXHX_STAGE0_DISABLE_PREPASSES=1`: `7064MB` (`-18.92%`)

Failfast `120s` family:
- Baseline: `8496MB`
- `HXHX_STAGE0_DISABLE_PREPASSES=1`: `7014MB` (`-17.44%`)

Repeated A/B (`reps=3`, failfast `120s`) families:
- `--no-line-directives` (`HXHX_STAGE0_NO_LINE_DIRECTIVES=1` / `-D ocaml_no_line_directives`)
  - Baseline median: `6609MB`
  - Mitigation median: `6494MB`
  - Median reduction: `1.74%`
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-061752/summary.json`
- `--no-expr-macros` (`HXHX_STAGE0_NO_EXPR_MACROS=1` / `-D hxhx_stage0_no_expr_macros`)
  - Baseline median: `6591MB`
  - Mitigation median: `6821MB`
  - Median reduction: `-3.49%` (regression)
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-063216/summary.json`
- `--no-external-macro-host` (`HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST=1` / `-D hxhx_stage0_no_external_macro_host`)
  - Baseline median: `6412MB`
  - Mitigation median: `6683MB`
  - Median reduction: `-4.23%` (regression)
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-065135/summary.json`
- `--no-stage3` (`HXHX_STAGE0_NO_STAGE3=1` / `-D hxhx_stage0_no_stage3`)
  - Baseline median: `6438MB`
  - Mitigation median: `6443MB`
  - Median reduction: `-0.08%` (neutral/regression)
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-070903/summary.json`
- `--no-stage3 --no-line-directives`
  - Baseline median: `6761MB`
  - Mitigation median: `5935MB`
  - Median reduction: `12.22%`
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-072426/summary.json`
- `--disable-prepasses --no-stage3 --no-line-directives`
  - Baseline median: `6385MB`
  - Mitigation median: `5810MB`
  - Median reduction: `9.01%`
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-073713/summary.json`
- `--no-stage3 --no-line-directives --no-external-macro-host --no-internal-tools`
  - Baseline median: `6716MB`
  - Mitigation median: `206MB`
  - Median reduction: `96.93%`
  - Artifact: `.hxhx/profile/stage0-regen-ab/20260305-081044/summary.json`
  - Caveat: this run family is not lane-equivalent (`baseline=status:error`, `mitigation=status:ok`);
    treat as a profiling signal only, not a default mitigation candidate.

## Interpretation

- The strongest single knob in this matrix remains `HXHX_STAGE0_DISABLE_PREPASSES=1`.
- `--no-line-directives` gives a small but stable win in this sample family (`~1-2%` median).
- `--no-expr-macros` is not viable as a mitigation in this probe family (regresses median peak RSS).
- `--no-external-macro-host` is not viable as a mitigation in this probe family (regresses median peak RSS).
- `--no-stage3` is effectively neutral in this probe family and does not move median peak RSS materially.
- Stacked combinations (`--no-stage3 --no-line-directives`, optionally with `--disable-prepasses`) show material gains in some runs, but with high variance and still below `20%` median in these repeated probes.
- The stacked combo that adds `--no-internal-tools` shows an outsized reduction, but it is not equivalent to the baseline lane in this probe family and stays profiling-only until behavior parity is demonstrated.
- In these sample families, reductions are material in some cases but still do not cross `20%` consistently.
- Keep this as an explicit troubleshooting/CI-tuning knob, not a global default change yet.

## Repro command pattern

```bash
HAXE_BIN="$(which haxe)" \
HXHX_STAGE0_NATIVE_HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" \
bash scripts/hxhx/profile-stage0-regen.sh \
  --policy prefer-native \
  --failfast <90|120> \
  --heartbeat 20 \
  [--no-opt] \
  [--no-inline] \
  [--disable-prepasses] \
  --out-dir <run-dir>
```
