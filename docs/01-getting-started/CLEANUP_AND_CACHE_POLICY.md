# Cleanup and Cache Policy

This repo intentionally generates many intermediate artifacts while bootstrapping `hxhx` and running Gate workloads.
Those artifacts are useful during execution, but most are disposable after the run.

Use the cleanup commands below to reclaim disk space deterministically.

## Quick commands

From repo root:

```bash
npm run clean:dry-run
npm run clean
npm run clean:tmp
npm run clean:deep
npm run clean:verbose
npm run clean:tmp:verbose
```

Command behavior:

- `clean:dry-run`: preview what would be removed in safe mode.
- `clean`: remove repo-local transient outputs (while preserving tracked placeholders such as fixture `out/.gitignore` files).
- `clean:tmp`: remove stale stage0 temp logs from OS temp dirs.
- `clean:deep`: includes heavier bootstrap caches (`bootstrap_out/_build`).
- `clean:verbose`: safe cleanup with full largest-first candidate listing, per-delete progress, and actual reclaimed size.
- `clean:tmp:verbose`: same reporting focused on stale stage0 temp logs.

## Artifact classes

### Must keep (committed / source of truth)

Do not delete these during normal cleanup:

- `packages/hxhx/bootstrap_out/*.ml` and companion dune files
- `packages/hxhx-macro-host/bootstrap_out/*.ml` and companion dune files

These are committed bootstrap snapshots used for stage0-free builds.

### Safe to remove (regenerable)

- root transient output:
  - `out/`
  - `out_ocaml*`
  - `dump_*`, `dump_out_*`
- package/tool/example/test transient outputs:
  - `**/out/`
  - `**/out_tmp*/`
  - `**/out_stage*/`
  - portable fixture runtime outputs (`stdout.txt`, `stderr.txt`)
- stage0 temp logs in OS temp dirs:
  - `hxhx-stage0-emit*.log*`
  - `hxhx-stage0-build*.log*`

### Deep-clean targets (larger rebuild cost)

- `packages/hxhx/bootstrap_out/_build`
- `packages/hxhx-macro-host/bootstrap_out/_build`

These are local build caches; deleting them is safe but the next build is slower.

## Log retention knobs

By default, stage0 scripts clean temporary logs after completion.

Set these only when debugging:

- `HXHX_KEEP_LOGS=1` keeps stage0 temp logs.
- `HXHX_LOG_DIR=/path/to/logs` writes logs to a stable directory.

Examples:

```bash
HXHX_KEEP_LOGS=1 bash scripts/hxhx/regenerate-hxhx-bootstrap.sh
HXHX_KEEP_LOGS=1 HXHX_LOG_DIR="$PWD/.tmp/hxhx-logs" bash scripts/hxhx/build-hxhx.sh
```

## Suggested cadence

- After heavy gate/build runs: `npm run clean:tmp` (or `npm run clean:tmp:verbose` when diagnosing disk usage).
- End of normal dev session: `npm run clean`.
- When disk pressure is high: `npm run clean:deep`.

## Guardrails

- Always run `git status --short` after cleanup to confirm no tracked files were removed.
- If you need to inspect candidates first, use `npm run clean:dry-run`.
