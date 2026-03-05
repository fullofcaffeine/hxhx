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

## Interpretation

- The strongest single knob in these runs is `HXHX_STAGE0_DISABLE_PREPASSES=1`.
- In this sample family, reductions are material but did not cross `20%` consistently.
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
