# Stage0 Bootstrap Throughput (2026-03-05)

This artifact records the worker/policy matrix captured for bead `haxe.ocaml-a0pt.1.1`.

## Run Shape

- Local profile: default compile knobs.
- CI-like profile: `HXHX_STAGE0_NO_INLINE=1` and `HXHX_STAGE0_DISABLE_PREPASSES=1`.
- Stage0 policies compared:
  - `warn` (wrapper baseline)
  - `prefer-native` (default policy)
- Worker settings sampled: `auto`, `2`, `4`
- Bounded probe mode: `HXHX_STAGE0_FAILFAST_SECS=90`, `HXHX_STAGE0_HEARTBEAT=20`

Command pattern used:

```bash
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=<warn|prefer-native> \
HXHX_STAGE0_NATIVE_HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" \
HAXE_BIN="$(which haxe)" \
HXHX_DUNE_JOBS=<auto|2|4> \
HXHX_STAGE0_NO_INLINE=<0|1> \
HXHX_STAGE0_DISABLE_PREPASSES=<0|1> \
HXHX_STAGE0_FAILFAST_SECS=90 \
HXHX_STAGE0_HEARTBEAT=20 \
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --incremental --no-verify --force --report-json <report.json>
```

Raw tabular artifact: `docs/benchmarks/stage0-bootstrap-throughput-2026-03-05.tsv`

## Results

| run | profile | policy | mode | jobs | total_sec | peak_rss_mb |
| --- | --- | --- | --- | --- | ---: | ---: |
| `local_wrapper_auto` | local | `warn` | wrapper | `auto` | 94 | 7262 |
| `local_native_auto` | local | `prefer-native` | native | `auto` | 95 | 2320 |
| `local_native_j2` | local | `prefer-native` | native | `2` | 94 | 3534 |
| `ci_wrapper_auto` | ci_like | `warn` | wrapper | `auto` | 94 | 4072 |
| `ci_native_auto` | ci_like | `prefer-native` | native | `auto` | 95 | 2052 |
| `ci_native_j4` | ci_like | `prefer-native` | native | `4` | 94 | 3279 |

## Interpretation

- Native stage0 selection (`prefer-native`) cuts observed peak RSS sharply versus wrapper mode in both profiles.
- `HXHX_DUNE_JOBS=auto` is kept as the default because fixed worker settings (`2`/`4`) increased peak RSS in this bounded window.
- Use fixed workers only when tuning for a known host/runner memory envelope.

## Important Note

All six runs are bounded probes (`status=error`) by design because `HXHX_STAGE0_FAILFAST_SECS=90` intentionally stops long emit runs. The objective here is early-phase throughput/memory comparability, not end-to-end completion timing.
