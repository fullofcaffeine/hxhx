# Cleanup and Cache Policy

This repo intentionally generates many intermediate artifacts while bootstrapping `hxhx` and running Gate workloads.
Those artifacts are useful during execution, but most are disposable after the run.

Use the cleanup commands below to reclaim disk space deterministically.

## Quick commands

From repo root:

```bash
npm run clean:dry-run
npm run clean
npm run clean:emergency:dry-run
npm run clean:emergency
npm run clean:tmp
npm run clean:deep
npm run clean:verbose
npm run clean:tmp:verbose
```

Command behavior:

- `clean:dry-run`: preview what would be removed in safe mode.
- `clean`: remove repo-local transient outputs (while preserving tracked placeholders such as fixture `out/.gitignore` files).
- `clean:emergency:dry-run`: explain which stale `.artifacts` entries can be reclaimed without first creating cleanup inventory files.
- `clean:emergency`: reclaim only those stale, unprotected `.artifacts` entries. Use this when normal cleanup cannot start because the disk is critically full.
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
- inactive dynamic macro-host workdirs under `.tmp/hxhx-macro-host-build.*`
- top-level `.artifacts` entries older than seven days, unless they carry a
  retention marker or a live owner PID (described below)
- stage0 temp logs in OS temp dirs:
  - `hxhx-stage0-emit*.log*`
  - `hxhx-stage0-build*.log*`

### Deep-clean targets (larger rebuild cost)

- `packages/hxhx/bootstrap_out/_build`
- `packages/hxhx-macro-host/bootstrap_out/_build`
- inactive autocreated hxhx snapshot build workdirs under `.tmp/hxhx-bootstrap-build.*`

These are local build caches; deleting them is safe but the next build is slower.

`npm run clean:deep` removes inactive autocreated `.tmp/hxhx-bootstrap-build.*`
directories and skips any workspace whose owner PID is still alive.
`scripts/hxhx/build-hxhx.sh` also prunes old autocreated workdirs before creating a new
snapshot build workspace. That automatic build-time pruning keeps the newest inactive
outputs by default (`HXHX_BOOTSTRAP_BUILD_RETAIN=2`). Set `HXHX_BOOTSTRAP_BUILD_PRUNE=0`
only when deliberately preserving multiple historical build outputs for debugging.

Normal `npm run clean` removes dynamic macro-host workdirs after their owning
test or shard process exits. Macro-host builders write a small PID lease into
the workdir, so cleanup skips a host that is still being compiled or exercised.
Callers that retain a dynamic host beyond the build script itself must pass
their live process ID through `HXHX_MACRO_HOST_LEASE_PID`.

## Local evidence retention

Generated reports under `.artifacts/` are useful while a result is being
reviewed, but they are not permanent source files. Normal safe/deep cleanup
considers each top-level entry stale after seven days. Override that age for a
specific run with `--artifacts-older-than`, for example:

```bash
bash scripts/dev/clean-artifacts.sh --safe --artifacts-older-than 14d
```

Put an empty `.hxhx-clean-retain` file anywhere inside an evidence tree when a
reviewer still needs that proof after the age limit. Remove the marker when the
proof can expire. A running producer may instead write its PID to
`.hxhx-clean-active.pid`; cleanup protects that tree only while the PID is
alive. Verbose and emergency dry runs print the protection reason.

Emergency cleanup deliberately has a smaller scope than normal cleanup. It
does not allocate candidate or size-report files and touches only stale,
unprotected top-level entries under this repository's `.artifacts/` directory.
It never scans or deletes another repository's temporary files. After it frees
enough space, run the normal safe/deep commands for the broader cleanup.

The dry run reports both reclaimable and protected evidence sizes. Compare the
reclaimable total with the filesystem shortage before concluding that cleanup
will help. Git objects and the Beads database are separate stores with separate
safety rules; inspect them with `npm run doctor:git-storage` and
`npm run doctor:beads-storage`. Large temporary directories owned by another
checkout should be reported to that checkout rather than silently deleted here.

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
- If normal cleanup cannot allocate its own inventory: preview with
  `npm run clean:emergency:dry-run`, then run `npm run clean:emergency`.

## Guardrails

- Always run `git status --short` after cleanup to confirm no tracked files were removed.
- If you need to inspect candidates first, use `npm run clean:dry-run`.
