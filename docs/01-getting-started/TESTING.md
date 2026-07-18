# Testing Strategy

This repo’s tests are intentionally split into **fast compiler checks** and **behavioral checks** that require an OCaml toolchain.

The goal is to:

- keep `npm test` fast enough for tight iteration
- still have realistic “this actually builds and runs under dune” coverage
- provide at least one **compiler-shaped acceptance workload** (not just unit tests / golden output)

## Quick start

From the repo root:

```bash
npm test
```

The default `npm test` loop intentionally excludes a small number of unusually heavy single-regression
compiler checks when they materially slow iteration. Run those targeted heavy checks separately:

```bash
npm run test:m14:heavy
```

Before running deeper compatibility gates, read:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`

If you have `ocamlc` + `dune` installed, this also runs:

- portable conformance fixtures (`test/portable/**`)
- example apps in both roots:
  - `examples/**`
  - `packages/reflaxe.ocaml/examples/**`
  (except acceptance-only examples)

To run heavier acceptance checks:

```bash
npm run test:acceptance
```

By default this uses `WORKLOAD_PROFILE=fast` (developer-friendly) and skips marked heavy workloads.
Use the full profile when you need full compiler-shaped coverage:

```bash
npm run test:acceptance:full
```

## Install the repository Git hooks

Run this once after cloning, and again after upgrading or reinstalling `bd`:

```bash
npm run hooks:install
```

The installer keeps the repository pre-commit checks and adds a narrow speed
guard in front of the Beads post-checkout hook. Git sometimes reports the same
branch and commit before and after a no-op rebase. No tracked checkout content
changed, so the guard skips only that redundant Beads import. A different
branch at the same commit, a changed commit, a file checkout, malformed hook
arguments, and manual `bd` commands still use the normal Beads path. A
pre-existing custom post-checkout hook is preserved and runs before the guard.
The companion post-commit hook records a successful local commit, so the next
no-op pull stays fast; any existing custom post-commit hook is also preserved.

This does not disable automatic issue synchronization. Continue to export
tracked issue data before commits as usual:

```bash
bd export -o .beads/issues.jsonl
```

To verify the installer and argument boundary with disposable fake hooks:

```bash
npm run test:hooks:post-checkout
```

Maintainers with `bd` installed can also prove a real changed checkout imports
new branch issue data in a temporary repository:

```bash
npm run test:hooks:post-checkout:real
```

If another hook installer replaces the guard, rerun `npm run hooks:install`.
The command is idempotent and preserves the installed Beads delegate. It fails
instead of overwriting two conflicting custom post-checkout hooks.

## Diagnose slow Beads commands

If `bd show`, `bd ready`, or `bd export` takes more than a few seconds, inspect
the local embedded database layout before assuming the issue count is the
problem:

```bash
npm run doctor:beads-storage
```

This diagnostic is read-only. It reports the database named by local Beads
metadata, any visible sibling databases, retained dropped-database storage, and
approximate disk use. A fresh clone without a local database reports `SKIP`; one
active database reports `PASS`; sibling or dropped databases report `WARN` and
exit with status 2. The command never removes or compacts data.

Embedded Dolt opens every visible database in its data directory. In July 2026,
an old database named `beads` contained zero issues but made a 1,910-issue
checkout spend 26.25 seconds and about 2.74 GB maximum resident memory on one
`bd show`. Removing that verified-empty sibling through Dolt's supported
database lifecycle reduced the same command to 1.44 seconds and about 161 MB.
The complete export remained byte-for-byte identical.

Treat a warning as data maintenance, not permission to delete a directory. The
maintainer recovery sequence is:

1. Export all records to a path outside the checkout:

   ```bash
   bd export --all -o <external-path>/issues-before-maintenance.jsonl
   ```

2. Create a full-history Dolt backup and sync it:

   ```bash
   bd backup init <external-path>/beads-full-backup
   bd backup sync
   ```

3. Restore that backup into a disposable Git repository with `bd init`, then
   run `bd backup restore --force <backup-path>`. Export again and compare the
   complete file and record counts. JSONL alone is not a full-history backup.
4. Identify the Dolt dependency embedded in the installed Beads binary with
   `go version -m "$(command -v bd)"`. Use that exact standalone Dolt version
   against the disposable copy first. Verify each sibling database's contents;
   a name that merely looks old is not enough evidence.
5. Only after the backup restore and empty-sibling proof, use the matching Dolt
   CLI to `DROP DATABASE` for that exact legacy database. Dolt keeps a reversible
   dropped copy. Re-run the export/hash/count checks and ordinary `bd` commands.
6. After those checks pass, `CALL dolt_purge_dropped_databases()` reclaims the
   reversible copies. This last step is permanent, so retain the external backup
   until the repository has been committed, pushed, and re-verified.

Do not remove `.beads/embeddeddolt` by hand. Do not use `bd gc` as a generic
storage fix: its default lifecycle includes deleting old closed issues, which is
not appropriate for this project's retained engineering record. A Beads version
upgrade is also a separate migration because it can rewrite tracker schema and
the tracked JSONL representation.

## Diagnose slow or noisy Git maintenance

If ordinary Git commands print an automatic-cleanup warning, or `.git` has grown
unexpectedly, inspect the local object store first:

```bash
npm run doctor:git-storage
```

This diagnostic is read-only. It reports loose objects, pack count and size,
the configured automatic-maintenance thresholds, cruft-pack policy, and any
retained `.git/gc.log`. A non-repository directory reports `SKIP`; a healthy
checkout reports `PASS`; a failed maintenance log, disabled automatic cleanup,
too many loose objects or packs, or Git-reported garbage reports `WARN` and
exits with status 2. It never runs `gc`, `repack`, `prune`, or `git config`.

Large snapshot rewrites and rebases can create many valid but unreachable Git
objects. Git 2.40.1 normally starts automatic maintenance at about 6,700 loose
objects. In July 2026, this checkout had 15,462 loose objects using 1.41 GiB.
A full object scan found 15,713 objects unreachable even from reflogs, while
`.git/gc.log` showed that automatic cleanup had stopped. Commits and pulls then
repeatedly printed the same warning.

The reviewed recovery used **cruft packs**. They compress unreachable objects
into a separate pack with their original modification times, so recent recovery
data does not have to remain as thousands of loose files. The standard two-week
prune grace remained in place; `--prune=now` was not used.

Use this backup-first sequence only when no other Git process is writing to the
checkout:

1. Require a clean status. Record `HEAD`, refs, reflogs, stashes, and worktrees;
   create an all-refs `git bundle`; and make a raw copy-on-write clone or full
   copy of `.git` outside the checkout. `git bundle` alone does not contain
   reflogs or unreachable recovery objects.
2. Verify the bundle with `git bundle verify`. Compare the copied refs and
   reflogs with the checkout and run `git fsck --full --no-dangling` against the
   raw copy.
3. Trial the exact maintenance command against another disposable copy first.
   Confirm refs, reflogs, reachable objects, index, worktrees, stashes, and
   working-tree status are unchanged.
4. Enable cruft packs for this checkout and preserve every reflog entry during
   the one-time repair:

   ```bash
   git config --local gc.cruftPacks true
   git -c gc.reflogExpire=never -c gc.reflogExpireUnreachable=never \
     gc --cruft --prune=2.weeks.ago
   ```

5. Re-run the semantic comparisons and a full `git fsck`. Verify
   `git gc --auto` is now a quiet no-op and `.git/gc.log` is absent. Keep the raw
   backup until the repository changes, tracker export, pull, and push are all
   verified.

Do not delete files below `.git/objects` by hand. Do not use immediate pruning
(`git prune --expire=now`), and do not use `git gc --aggressive` for routine
recovery. The installed Git manual warns that immediate pruning raises
corruption risk when a writer is concurrent, while aggressive repacking costs
much more and is usually the wrong tradeoff without dedicated benchmarks.

## Formatting Haxe code

Use the official Haxe formatter through `haxelib`.

For files you just changed:

```bash
npm run format:hx:changed
npm run guard:hx-format:changed
```

For the repo-wide formatting guard:

```bash
npm run guard:hx-format
```

`npm run guard:hx-format` runs `scripts/lint/hx_format_guard.sh`. That shell
script is only the stable npm/CI entrypoint: it moves to the repo root and calls
`scripts/lint/hx-format-guard.js`.

The Node helper does not define its own style rules. It still delegates to
`haxelib run formatter --check`; it just splits tracked `.hx` files into
deterministic, line-balanced chunks and checks those chunks in parallel because
Haxe Formatter does not provide a built-in jobs flag. The default `auto` mode caps
at four jobs. Use `HX_FORMAT_JOBS=1 npm run guard:hx-format` when you want serial
debug output, or set `HX_FORMAT_JOBS=<n>` to choose a specific chunk count.

For the fast-vs-full validation map, current-source `hxhx` build reuse, and
timeout helper policy, see:
`docs/01-getting-started/FAST_LOCAL_VALIDATION.md`

## Portable semantic-diff seed lane

Run the first shared family semantic-diff slice (repo-authored fixtures only):

```bash
npm run test:stdlib:semantic-diff:seed
```

Notes:

- Slice source: `test/portable/semantic_diff/corpus_v1.json` (`core_seed_v1`)
- Fixture contribution rules: `test/portable/semantic_diff/CONTRIBUTING.md`
- Deterministic typed generator smoke:
  - `npm run test:stdlib:semantic-diff:generator`
- Comparator + normalized-output smoke:
  - `npm run test:stdlib:semantic-diff:comparator`
- Minimizer + exporter smoke:
  - `npm run test:stdlib:semantic-diff:minimizer`
- CI lane driver (profile via env: `SEMANTIC_DIFF_PROFILE=pr|nightly`):
  - `npm run test:stdlib:semantic-diff:lane`
- CI scoped PR canary (`.github/workflows/semantic-diff.yml`):
  - runs only when scoped files change (`packages/reflaxe.ocaml/std/**`, `packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/**`, runtime-plan hooks in `OcamlCompiler.hx` / `OcamlRuntimeMode.hx`)
  - markers: `SEMANTIC_DIFF_LITE_SCOPE:RUN` then `SEMANTIC_DIFF_LITE:PASS`
  - artifact bundle: `semantic-diff-pr-artifacts`

## Cleanup after heavy runs

Long upstream/gate/bootstrap runs can leave sizeable temp/build artifacts.

From repo root:

```bash
npm run clean:dry-run
npm run clean
npm run clean:tmp
npm run clean:deep
```

Bootstrap smoke failures now bundle compact diagnostics into `.artifacts/bootstrap-smoke-failures/`
by default instead of retaining the full `.tmp` build root. Set `HXHX_KEEP_TMP_ON_FAIL=1`
only when you explicitly need the entire failing temp tree.

Details and retention knobs (`HXHX_KEEP_LOGS`, `HXHX_LOG_DIR`) are documented in:
`docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md`

## Upstream Haxe acceptance gates (Haxe-in-Haxe path)

These are **not** part of `npm test` because they depend on:

- a local checkout of the upstream Haxe compiler repo
- extra toolchains / deps (`haxelib`, network for pinned libs, etc.)

Plain-English gate map:

- **Gate 1**: “core compatibility” — upstream unit macro suite.
- **Gate 2**: “bigger macro workflow” — upstream `runci` Macro target.
- **Gate 3**: “target matrix” — staged target workflows (`Macro`, `Js`, `Neko`, opt-in extras).

Mainstream compatibility quick command set:

```bash
npm run test:upstream:unit-macro-stage3-no-emit
npm run test:upstream:runci-macro-stage3-direct
npm run test:upstream:display-stage3-no-emit
npm run test:upstream:replacement-ready:strict
```

Macro runtime mode default/rollback for these lanes:

- default is `inproc` (no external macro-host spawn)
- emergency fallback is `external-host`

```bash
# Force fallback mode for triage if needed:
HXHX_MACRO_RUNTIME_MODE=external-host npm run test:upstream:unit-macro-stage3-no-emit
```

Gate 1 (unit macro suite) uses the upstream file:

- `tests/unit/compile-macro.hxml`

Run it via the `hxhx` harness:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Notes:

- Today `npm run test:upstream:unit-macro` is a **native/non-delegating bring-up rung**:
  it routes the upstream `compile-macro.hxml` through `hxhx --hxhx-stage3 --hxhx-emit-full-bodies` to exercise
  resolver + typer + macro-host plumbing plus OCaml emit/build wiring without invoking a stage0 `haxe` binary.
  - The historical stage0-shim baseline remains available as:
    `npm run test:upstream:unit-macro-stage0`
  - CI cadence:
    - per-push/PR macro smoke in `.github/workflows/gate1-lite.yml` (`test:upstream:unit-macro-stage3-no-emit`)
    - weekly full Linux baseline in `.github/workflows/gate1.yml`, plus manual `workflow_dispatch` override (`run_upstream_unit_macro=true`).
  - Gate1 unit-macro rungs now fail fast across hosts (including macOS), and all Stage3 rungs (`no-emit`, `type-only`, `emit`) run with `HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1`.
  - The Stage3 `emit` rung fails on OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`).
- By default, upstream gate runners look for `vendor/haxe`; override with `HAXE_UPSTREAM_DIR=/path/to/haxe`.
- “Replacement-ready” acceptance is defined in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
  That document also clarifies what we mean by “compile Haxe” and how Stage0→Stage2 bootstrapping works.

Gate 2 (runci Macro target) runs the upstream `tests/runci/targets/Macro.hx` suite:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Notes:

- The **full upstream Gate 2** run is not part of PR/push CI (it is network-heavy and relies on external toolchains).
  It runs weekly in `.github/workflows/gate2.yml` and remains manually triggerable via `workflow_dispatch` + `run_upstream_macro=true`.
- PR/push CI gets a lightweight Gate 2 signal from `.github/workflows/gate2-lite.yml` (fast workloads via `npm run test:workloads`).
- Host toolchain requirements and macOS sys-stage caveats are documented in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
- Debugging: set `HXHX_GATE2_MISC_FILTER=<pattern>` to run only a subset of `tests/misc` fixtures.
- By default this uses a **non-delegating** Gate 2 mode (`HXHX_GATE2_MODE=stage3_no_emit_direct`): it runs the same stage
  sequence as upstream runci Macro, but routes every `haxe` invocation through `hxhx --hxhx-stage3 --hxhx-no-emit`.
  - To run the historical “stage0 shim” harness instead, set `HXHX_GATE2_MODE=stage0_shim`.
  - `HXHX_GATE2_MODE=stage3_emit_runner` is an experimental rung: it tries to compile+run the upstream RunCi runner under the
    Stage3 bootstrap emitter (intended to run upstream `tests/RunCi.hx` unmodified once Stage3 is ready).
    - This runner now defaults to bootstrap snapshots for faster iteration.
    - This runner treats OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`) as hard failures.
    - Set `HXHX_FORCE_STAGE0=1` if you explicitly want to rebuild `hxhx` from source before running it.
    - Timeout/heartbeat knobs:
      - `HXHX_GATE2_RUNCI_TIMEOUT_SEC` (default `600`; set `0` to disable timeout)
      - `HXHX_GATE2_RUNCI_HEARTBEAT_SEC` (default `20`; set `0` to disable heartbeat lines)
      - Heartbeat line format: `gate2_stage3_emit_runner_heartbeat elapsed=<sec>s subinvocations=<n> last="<command>"`
      - Gate2 summary now prints `subinvocations=<n>` and `last_subinvocation=<cmd>` for direct/runner modes.
- `HXHX_GATE2_MODE=stage3_emit_runner_minimal` is a bring-up rung that patches `tests/RunCi.hx` *in the temporary worktree*
  to a minimal harness so we can at least prove sub-invocation spawning.
- `HXHX_GATE2_MACRO_STOP_AFTER=<stage>` (direct mode only) stops the Macro sequence after a named stage and prints explicit markers.
  - Supported: `unit`, `display`, `sourcemaps`, `nullsafety`, `misc`, `resolution`, `sys`, `compiler_loops`, `threads`, `party`.
  - Useful for targeted iteration without running the full Gate2 matrix.

Focused display rung (non-delegating, direct Macro sequence up to display):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro-stage3-display
```

Success markers:
- `macro_stage=display status=ok`
- `gate2_display_stage=ok`
- `gate2_stage3_no_emit_direct=ok stop_after=display`

Notes:
- This focused rung sets `HXHX_GATE2_SKIP_UNIT=1` so it can isolate display semantics
  without being blocked by unrelated `tests/unit` bring-up gaps.
- The focused display rung is fail-fast (no Darwin-specific retry/skip fallback path).
- Current baseline (2026-02-21): `unsupported_exprs_total=0`, `unsupported_files=0`.

### Bootstrap stage map (quick reference)

Use this when you want the repo to function as a compiler-bootstrap example:

- Plain-language self-hosting status/checklist (includes a pass/partial/not-yet matrix):
  - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`

- Stage0-free native refresh prototype:
  - Command: `npm run hxhx:probe:stage0-free-refresh`
  - Scope: builds `hxhx` from committed snapshots with `HXHX_FORBID_STAGE0=1`, then runs Stage3
    `--hxhx-emit-full-bodies --hxhx-no-run` on the repo-owned `demo.A` fixture.
  - Scaling probe: set `HXHX_STAGE0_FREE_REFRESH_SCOPE=hxhx-type-only` to target the real
    `packages/hxhx/src` + `packages/hxhx-core/src` graph in Stage3 type-only mode without writing
    `packages/hxhx/bootstrap_out`.
  - Full-emission dry-run: set `HXHX_STAGE0_FREE_REFRESH_SCOPE=hxhx-full-emit` to run the same
    real source graph through Stage3 full-body emit/build without promoting snapshots.
  - Timeout guard: `HXHX_STAGE0_FREE_REFRESH_STAGE3_TIMEOUT_SEC` bounds the Stage3 probe
    (defaults: demo `120`, hxhx type-only `900`, hxhx full-emit `1800`; set `0` to disable).
  - Output: `.tmp/stage0-free-bootstrap-refresh-probe/summary.txt`
  - Artifact hygiene: the probe removes the temporary `hxhx` bootstrap build and Stage3 compiled
    byproducts by default; set `HXHX_STAGE0_FREE_REFRESH_KEEP_BUILD=1` or
    `HXHX_STAGE0_FREE_REFRESH_KEEP_DUNE_BUILD=1` only when you need local diagnostics.

- Full 1.0 performance policy:
  - Policy doc: `docs/00-project/FULL1_PERF_PARITY_POLICY.md`
  - Guard: `npm run guard:full1-perf-policy`
  - Contract marker: `FULL1_PERF_POLICY:PASS`
  - Measured evidence marker: `FULL1_PERF_PARITY:PASS`
  - Boundary: Full 1.0 performance evidence compares stage0-free `hxhx` runtime lanes against
    upstream Haxe 4.3.7. Stage0 bootstrap regeneration memory is maintenance-only evidence.

- **Stage0**: external `haxe` compiles repo Haxe sources to OCaml.
  - Main maintainer command: `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`
  - Stage0 haxe binary selection policy (regen lane):
    - default: `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native`
    - optional strict mode: `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=require-native`
    - wrapper baseline mode: `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=warn`
    - explicit native candidate override: `HXHX_STAGE0_NATIVE_HAXE_BIN=/abs/path/to/haxe`
    - optional lower-memory compile knob: `HXHX_STAGE0_NO_OPT=1` (adds `--no-opt`)
    - optional lower-memory compile knob: `HXHX_STAGE0_NO_INLINE=1` (adds `--no-inline`)
    - optional OCaml GC tuning for stage0 process: `HXHX_STAGE0_OCAMLRUNPARAM=s=4M`
  - Regen report JSON (`--report-json`) includes deterministic selection fields:
    - `haxe_bin_requested`, `haxe_bin_resolved`, `haxe_bin_mode`, `haxe_bin_policy`, `haxe_bin_switched`
    - `stage0_disable_prepasses`, `stage0_no_opt`, `stage0_no_inline`, `stage0_no_native_parser`, `stage0_no_hx_parser`, `stage0_no_expr_macros`, `stage0_no_external_macro_host`, `stage0_no_stage3`, `stage0_no_internal_tools`, `stage0_no_display`, `stage0_ocaml_only`, `stage0_no_line_directives`, `stage0_no_source_normalize_extract`, `stage0_no_native_decode_extract`, `stage0_no_parser_scan_extract`, `stage0_ocamlrunparam`
    - `stage0_observability.heartbeat_peak_rss_mb`, `stage0_observability.heartbeat_peak_tree_rss_mb`, and `stage0_observability.heartbeat_trace_file` (plus heartbeat samples/interval)
  - Selection-only probe (no emit/copy/verify): `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --stage0-selection-only`
  - Wrapper-vs-native benchmark utility (policy compare + RSS summary):
    - `HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm HXHX_BOOTSTRAP_BENCH_DUNE_JOBS=auto,2,4 HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES=1 npm run hxhx:bench:bootstrap-regen`
    - `warm` reuses generated output, not compiler-server state: every measured sample gets a fresh server matched to the selected upstream-Haxe wrapper/direct-binary policy.
    - Both policy labels still describe upstream Haxe stage0; neither is native `hxhx`. The current peak-RSS column excludes the server process.
    - Bootstrap regeneration asks Reflaxe to keep its generated-file metadata ID at zero. That ID is normally only a compile counter; fixing it at zero prevents two otherwise identical snapshot refreshes from looking different.
    - The benchmark report lists every changed path under `packages/hxhx/bootstrap_out`, including untracked generated files, with before/after SHA-256 digests. This makes it clear whether the committed snapshot is behind the Haxe source or the generator itself is changing unpredictably.
    - include compile knobs in benchmark runs:
      `HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT=1`, `HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE=1`, `HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES=1`, and/or `HXHX_BOOTSTRAP_BENCH_STAGE0_OCAMLRUNPARAM=s=4M`
    - benchmark evidence artifact (local + CI-like worker/policy matrix):
      `docs/benchmarks/STAGE0_BOOTSTRAP_THROUGHPUT_2026_03_05.md`
    - stage0 memory knob matrix evidence (native lane probe family):
      `docs/benchmarks/STAGE0_MEMORY_KNOB_MATRIX_2026_03_05.md`
  - Stage0 contributor profiling helper (telemetry + summary):
    - `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20`
    - Before regeneration begins, the profiler runs the same local-capacity preflight as other heavyweight gates. Saturated local runs stop with retryable exit code `75`; use `--capacity-policy warn` to retain a warning-only sample or `--capacity-policy off` only when deliberately accepting contaminated timing conditions.
    - optional OCaml runtime tuning: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --ocamlrunparam s=4M`
    - optional native-parser bypass: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-native-parser`
    - optional pure-Haxe parser fallback trimming: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-hx-parser`
    - optional Stage3 expression-macro graph trimming: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-expr-macros`
    - optional external macro-host runtime-path trimming: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-external-macro-host`
    - optional Stage3 native-lane path trimming: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-stage3`
    - optional internal bring-up CLI path trimming (profiling-only lane): `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-internal-tools`
    - optional Stage3 display synthesis path trimming (profiling-only lane): `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-display`
    - optional stage0 compile-graph minimization (OCaml-only backend graph): `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --ocaml-only`
    - optional generated-output metadata trimming: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-line-directives`
    - optional parser-helper inline baseline for source-level A/B profiling: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-source-normalize-extract`
    - optional parser native-decode inline baseline for source-level A/B profiling: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-native-decode-extract`
    - optional parser helper-scan inline baseline for source-level A/B profiling: `npm run hxhx:profile:stage0-regen -- --failfast 65 --heartbeat 20 --no-parser-scan-extract`
    - repeated baseline-vs-mitigation memory A/B runner:
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --mitigation-args "--disable-prepasses"`
    - repeated parser-source extraction A/B runner:
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --baseline-args "--no-source-normalize-extract" --mitigation-args "" --parity-mode status-exit`
    - repeated parser native-decode extraction A/B runner:
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --baseline-args "--no-native-decode-extract" --mitigation-args "" --parity-mode status-exit`
    - repeated parser helper-scan extraction A/B runner:
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --baseline-args "--no-parser-scan-extract" --mitigation-args "" --parity-mode status-exit`
    - optional parity gate for equivalent baseline/mitigation outcomes (exit code `4` on mismatch):
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --mitigation-args "--disable-prepasses" --parity-mode status-exit --require-status-parity`
    - enforce a reduction threshold in CI/local scripts (exit code 3 on miss):
      `npm run hxhx:profile:stage0-regen-ab -- --reps 3 --failfast 120 --mitigation-args "--disable-prepasses" --min-reduction-pct 20 --reduction-metric median`
    - emits `.hxhx/profile/stage0-regen/<timestamp>/summary.txt` with top class contributors (`peak_rss_source=report|stdout_fallback`, `peak_tree_rss_mb`, and heartbeat trace path).
    - emits `.hxhx/profile/stage0-regen/<timestamp>/stage0_heartbeat_trace.jsonl` with compact driver-side samples for runs that do not reach Reflaxe progress hooks.
    - emits `.hxhx/profile/stage0-regen/<timestamp>/heartbeat_summary.json` with sample count, invalid lines, elapsed/log growth, peak focus RSS, peak process-tree RSS, and top samples from the heartbeat trace.
    - emits `.hxhx/profile/stage0-regen/<timestamp>/progress_summary.json` for deterministic class/checkpoint aggregation.
    - emits `.hxhx/profile/stage0-regen/<timestamp>/capacity_report.json` so every timing sample records whether host capacity passed, warned, or was explicitly disabled.
    - `--out-dir` accepts relative or absolute paths. The runner resolves the path before its nested build changes directories and rejects a successful run when the required progress telemetry is missing, so an incomplete measurement cannot look green.
    - summarize any existing progress log: `node scripts/hxhx/summarize-stage0-progress.js --input <reflaxe_ocaml_progress.log> --top 15 --json-out <out.json>`
    - summarize any existing heartbeat trace: `npm run hxhx:profile:stage0-heartbeat-summary -- --input <stage0_heartbeat_trace.jsonl> --top 10 --json-out <out.json>`
    - compare multiple run summaries: `npm run hxhx:profile:stage0-compare -- --summary-dir <run1> --summary-dir <run2> --summary-dir <run3> --min-presence 2 --sort median --json-out <compare.json>`
    - print baseline-vs-latest regression table from latest N summaries: `npm run hxhx:profile:stage0-hotspot-baseline -- --root .hxhx/profile/stage0-regen --samples 5 --min-presence 2 --sort median --json-out .hxhx/profile/stage0-regen/compare.latest.json`
  - Script preflight checks for stale `haxe --wait` / `--server-connect` processes before emit.
    - Opt-in safe cleanup (repo-owned only): `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --kill-repo-server`
    - Opt-in global cleanup (unsafe): `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --kill-all-haxe-servers`
  - Optional repo-owned server reuse:
    - `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --use-repo-server --keep-repo-server --incremental --no-verify`
    - Direct helper: `bash scripts/hxhx/haxe-server.sh start|status|stop`
    - The helper records the launcher and its descendants after readiness. `stop`, failed startup, and interrupted startup terminate the complete recorded tree, including a real native Haxe child spawned by a Node/Lix wrapper.
  - Optional skip-if-unchanged:
    - `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --skip-if-unchanged --incremental --no-verify`
  - Faster local iteration (reuse previous emit output + skip verify):
    - `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast`
    - Equivalent env knobs:
      - `HXHX_BOOTSTRAP_CLEAN_OUT=0` (incremental emit)
      - `HXHX_BOOTSTRAP_VERIFY=0` (skip snapshot verify)
  - If heartbeat is disabled (`HXHX_STAGE0_HEARTBEAT=0`), optional diagnostics are available via
    `HXHX_STAGE0_DIAG_EVERY=<seconds>` (or `--diag-every <seconds>`).
- **Stage1**: build `hxhx` from committed bootstrap snapshot (`out.bc` / native fallback).
  - Command: `bash scripts/hxhx/build-hxhx.sh`
  - Autocreated `.tmp/hxhx-bootstrap-build.*` workdirs are pruned on later runs; tune with `HXHX_BOOTSTRAP_BUILD_RETAIN=<n>` or disable with `HXHX_BOOTSTRAP_BUILD_PRUNE=0`.
  - Stage0 source lane connect options (used when `HXHX_FORCE_STAGE0=1`):
    - explicit `HAXE_CONNECT=<port>` override (highest precedence)
    - helper-managed reuse: `HXHX_STAGE0_USE_REPO_SERVER=1` (with optional `HXHX_STAGE0_KEEP_REPO_SERVER=1`)
    - stuck connect handoff detector: `HXHX_STAGE0_CONNECT_IDLE_SECS=<seconds>` (default `180`; `0` disables auto-retry without `--connect`)
  - Observability knobs: `HXHX_BOOTSTRAP_HEARTBEAT=20` (default; set `0` to disable) and `HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS=0` (optional timeout).
  - Dune worker knob: `HXHX_DUNE_JOBS=auto|<N>` (defaults to `auto`; set `HXHX_DUNE_JOBS=4` for a fixed worker cap when tuning memory/throughput).
- **Stage2**: stage1 builds stage2; compare behavior/codegen stability.
  - Command: `npm run test:upstream:stage2`
- **Gate checks**: validate against upstream behavior oracles.
  - Gate1: `npm run test:upstream:unit-macro`
  - Gate2: `npm run test:upstream:runci-macro`
  - Display end-to-end smoke: `npm run test:upstream:display-stage3-emit-run-smoke`

Dedicated display smoke rung (non-delegating Stage3 no-emit):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-no-emit
```

Notes:

- This validates `--display <file@mode>` request handling directly through `hxhx --hxhx-stage3 --hxhx-no-emit`.
- It also includes a `--wait stdio` framed-protocol smoke check (non-delegating server lifecycle).
- It intentionally does **not** require full upstream display semantic parity yet.
- Socket server/client protocol regression coverage lives in `npm run test:hxhx-targets`
- Stage3 receiver-call over-application regression (`other.add(n)` should not become `add (this_) (other) (n)`) is covered by `npm run test:m14:hih-emitter-receiver-call` (source-level, no Stage0 rebuild needed).
- Backend registry descriptor/selection regression coverage is in `npm run test:m14:backend-registry`.
- Neko native backend smoke coverage is in `npm run test:m14:neko-native-backend-smoke`.
- HashLink native backend boundary smoke coverage is in `npm run test:m14:hashlink-native-backend-smoke`.
- OCaml target-core wrapper wiring regression coverage is in `npm run test:m14:target-core-wiring`.
- JS target-core wrapper wiring regression coverage is in `npm run test:m14:js-target-core-wiring`.
- Statement-level parser coverage for try/catch + throw is in `npm run test:m14:hih-try-throw-stmt`.
- JS statement lowering coverage for try/catch + throw is in `npm run test:m14:js-stmt-try-throw`.
- JS statement multi-catch dispatch lowering coverage is in `npm run test:m14:js-stmt-multi-catch`.
- JS expression lowering regressions are covered by `npm run test:m14:js-expr-new-array` and
  `npm run test:m14:js-expr-range` and `npm run test:m14:js-expr-array-comprehension` and
  `npm run test:m14:js-expr-switch`.
- `npm run test:hxhx-targets` validates runtime delegation guard behavior when the current
  `hxhx` binary exposes `HXHX_FORBID_STAGE0` shim enforcement.
- For quicker local reruns after a successful build, you can reuse an existing binary:
  `HXHX_BIN=packages/hxhx/out/_build/default/out.bc npm run test:hxhx-targets`.
- `npm run test:hxhx-targets` defaults to stage0 lane builds (`HXHX_FORCE_STAGE0=1`);
  set `HXHX_FORCE_STAGE0=0` to run against stage0-free bootstrap snapshots.
- Stage0 build-lane observability defaults:
  - default heartbeat is bounded (`HXHX_STAGE0_HEARTBEAT=30`)
  - default failfast is bounded (`HXHX_STAGE0_FAILFAST_SECS=7200`)
  - optional RSS guard (`HXHX_STAGE0_MAX_RSS_MB=<limit>`) hard-stops runaway stage0 builds.
  - optional lower-memory compile mode (`HXHX_STAGE0_NO_INLINE=1`) adds `--no-inline` to stage0 source builds.
  - override defaults for this test lane with:
    - `HXHX_TARGETS_STAGE0_HEARTBEAT_DEFAULT=<sec>`
    - `HXHX_TARGETS_STAGE0_FAILFAST_DEFAULT=<sec>`
- CI split for stability:
  - `Stage0-free smoke` runs `bash scripts/hxhx/check-stage0-policy.sh release`
    (runtime delegation guard + macro-host selftest + dist stage0 policy check).
  - `Tests` runs `npm run test:hxhx-targets` with `HXHX_FORCE_STAGE0=0` (stage0-free bootstrap path).
  - `Gate 1 Lite` workflow (`.github/workflows/gate1-lite.yml`) runs the upstream macro smoke rung (`test:upstream:unit-macro-stage3-no-emit`) on every push/PR.
  - `Gate 2 Lite` workflow (`.github/workflows/gate2-lite.yml`) runs fast workloads on every push/PR.
  - `Plugin matrix (strict)` job in `.github/workflows/ci.yml` runs `npm run test:plugins:strict-matrix`
    on every push/PR:
    - native backend plugin build smoke (`npm run test:hxhx:native-plugin-build-smoke`) producing native plugin artifact (`.cmxs`/`.cma`) + manifest
    - plugin init scaffold smoke (`npm run test:hxhx:plugin-init-scaffold-smoke`) proving one-command generated scaffolds stay buildable through `hxhx plugin build` / `hxhx plugin test`
    - promotion backend smoke (`npm run test:hxhx:promotion-backend-smoke`) proving promoted provider flow emits a native plugin artifact and compiles/runs through Stage3 backend selection
    - promotion eval smoke (`npm run test:hxhx:promotion-eval-smoke`) proving generated eval adapter artifacts load through `eval.vm.Context.loadPlugin`
      (if local `haxe` and local OCaml toolchain ABI differ, the smoke emits `PROMOTION_EVAL_SMOKE:SKIP_HOST_ABI` and keeps the lane non-blocking)
    - macro-module dynlink smoke (`npm run test:hxhx:macro-module-dynlink-smoke`) proving promoted native macro module load/run via Stage4 RPC
      (`macro.loadNativeModule` + `macro.runNativeExpr`) with negative diagnostics for plugin-ID mismatch and missing entrypoint
    - native backend plugin runtime smoke (`npm run test:hxhx:native-plugin-runtime-smoke`) for load + emit + run + negative diagnostics
      (required in strict plugin matrix; runs `.cma` artifact when `HXHX_BIN` is bytecode and `.cmxs` when native)
    - macro-library smoke (`reflaxe.ocaml` build fixture + Stage3 `--library` activation from `haxe_libraries/*.hxml`)
    - eval.vm plugin API smoke (`eval.vm.Context.loadPlugin`)
    - Stage3 plugin fixture (`hxhxmacros.PluginFixtureMacros.init()`) with hook/classpath/module emission checks.
  - external official plugin-hosted proof lane (manual/non-required):
    - `npm run test:hxhx:reflaxe-elixir-todo-pilot`
    - fetches external todo-app Haxe sources, promotes a native plugin artifact, and compiles/runs a deterministic marker sample through Stage3 backend selection.
    - this is the current official native `hxhx` surface for external `reflaxe-elixir` pressure testing.
    - local runs clean temporary build output by default; set `HXHX_PILOT_ARTIFACT_DIR=.artifacts/xbnp/reflaxe-elixir-todo-pilot/manual` to retain the small evidence bundle
    - the scheduled/manual GitHub lane uploads `reflaxe-elixir-promotion-native-<run-id>` with `reflaxe-elixir-promotion-native.summary.json`, promotion checksums, compile log, and node output
    - detailed guide: `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
  - external repo-harness verifier (manual/non-required):
    - `npm run test:hxhx:reflaxe-elixir-native-verify`
    - runs upstream-vs-native verification against the real `vendor/reflaxe-elixir` harness entrypoints and writes retained evidence under `.artifacts/pybm/reflaxe-elixir-native-verify/<run-id>/`
    - this runner is currently a diagnostic baseline for raw source-based `hxhx-as-haxe` workflows, not the official native promotion contract
    - the official native contract for external `reflaxe-elixir` pressure tests is the promoted host-adapter/plugin path documented in `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
    - summary JSON now separates those lanes explicitly:
      - `proof.officialNativePath`
      - `proof.diagnosticSourceHostBaseline`
    - supports lane narrowing with `PYBM_LANES=<csv>`; useful first lanes are:
      - `ci-guards`
      - `runtime-smoke`
      - `todo-build-tests`
      - `todo-mix-test`
      - `qa-sentinel`
    - current verifier artifacts include:
      - `ci-guards`: `.artifacts/pybm/reflaxe-elixir-native-verify/20260320-015843/reflaxe-elixir-native-verify.summary.json`
      - `npm-test`: `.artifacts/pybm/reflaxe-elixir-native-verify/20260319-172613/reflaxe-elixir-native-verify.summary.json`
      - `qa-sentinel`: `.artifacts/pybm/reflaxe-elixir-native-verify/20260318-220339/reflaxe-elixir-native-verify.summary.json`
      - `todo-mix-test`: `.artifacts/pybm/reflaxe-elixir-native-verify/20260320-015723/reflaxe-elixir-native-verify.summary.json`
      - `todo-build-tests`: `.artifacts/pybm/reflaxe-elixir-native-verify/20260318-220548/reflaxe-elixir-native-verify.summary.json`
    - current official native promoted path result:
      - `proof.officialNativePath.status = pass`
      - the promoted host-adapter/plugin path compiles, selects `provider/js-native-wrapper`, and the todo pilot runtime passes
    - current diagnostic source-host split:
      - `ci-guards`: upstream and native both pass
      - `npm-test`: upstream now passes after verifier Mix preflight; native source-host baseline classifies as `native_source_target_unimplemented`
      - `todo-mix-test`: upstream now passes after verifier Mix preflight; native source-host baseline classifies as `no_target_selected`
      - `todo-build-tests`: upstream passes; native source-host baseline classifies as `no_target_selected`
      - `qa-sentinel`: upstream passes; native source-host baseline classifies as `no_target_selected`
      - this means the official promoted native path is green, while the remaining raw source-host gaps are either:
        - the already-tracked source-host adapter gap for ordinary source-based Reflaxe Elixir HXML workflows, or
        - narrower host-routing failures such as `no_target_selected`
  - `Stage0 Source Smoke` workflow (`.github/workflows/stage0-source-smoke.yml`) separately validates
    stage0 source-build behavior (`HXHX_FORCE_STAGE0=1`) on a nightly/manual lane
    (tuned with `HXHX_STAGE0_OCAML_BUILD=byte`, `HXHX_STAGE0_DISABLE_PREPASSES=1`, and `HXHX_STAGE0_NO_INLINE=1`; the lane enforces `>=8GB` swapfile capacity on ubuntu runners to reduce OOM kills).
  - each Stage0 Source Smoke run emits `stage0_peak_tree_rss_mb=<n>` and uploads
    `stage0_source_build.log` plus stage0 profile/hotspot artifacts as workflow artifacts.
  - local telemetry helpers:
    - parse one build log: `bash scripts/ci/extract-stage0-peak-rss.sh <stage0_source_build.log>`
    - aggregate recent GitHub samples (default 5): `bash scripts/ci/stage0-source-rss-baseline.sh --allow-partial`
    - include failed runs in the sample set for early diagnosis: `bash scripts/ci/stage0-source-rss-baseline.sh --include-failures --allow-partial`
    - aggregate recent stage0 hotspot summaries from workflow artifacts: `npm run hxhx:profile:stage0-hotspot-gh-baseline -- --allow-partial --current-summary <progress_summary.json>`
  - current ubuntu-latest success baseline (5 samples, 2026-02-20): `min=15028MB`, `median=15103MB`, `avg=15134.4MB`, `max=15253MB`; CI policy keeps `HXHX_STAGE0_MAX_RSS_MB=0` (cap disabled) to avoid false-positive kills near runner limits.
  - local stage0 policy checks:
    - `npm run test:stage0-policy` (runtime guard)
    - `npm run test:stage0-policy:release` (runtime + release/dist strict-mode checks)
- `npm run test:hxhx-targets` also validates request-scoped Stage3 provider loading:
  `HXHX_BACKEND_PROVIDERS=backend.js.JsBackend` must override `js-native` backend selection
  (`backend_selected_impl=provider/js-native-wrapper`) while fallback stays `builtin/js-native`.
- If the current `hxhx` binary does not expose native JS lane `--js <file>`, `npm run test:hxhx-targets` skips
  native-JS-only checks and prints explicit skip markers (dedicated JS smoke CI still enforces the lane).
  (`--wait <host:port>` + `--connect <host:port>` roundtrip).

Dedicated display full-emit warm-output stress rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-stress
```

Notes:

- This runs upstream `tests/display/build.hxml` repeatedly under
  `hxhx --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run`.
- It intentionally reuses the same `--hxhx-out` directory across iterations to catch
  warm-output determinism/linking regressions.
- Tune iteration count with `HXHX_DISPLAY_EMIT_STRESS_ITERS=<n>` (default: `10`).

Dedicated display full-emit + run smoke rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-run-smoke
```

Notes:

- This runs upstream `tests/display/build.hxml` with execution enabled
  (`hxhx --hxhx-stage3 --hxhx-emit-full-bodies`, no `--hxhx-no-run`).
- It now requires successful execution (`run=ok`) and fails on any non-zero exit.
- It also explicitly fails hard on segfault-shaped regressions (`Segmentation fault` / `EXC_BAD_ACCESS` / rc `139`).
- On success it emits `display_utest_suite=ok` after validating this is the utest workload
  and that `resolved_modules` meets a minimum threshold (default `80`, configurable via
  `HXHX_DISPLAY_EMIT_RUN_MIN_RESOLVED`).

### Stage 2 reproducibility rung (Stage1 builds Stage2)

This is a local bootstrap sanity check:

- Build stage1 `hxhx` (native OCaml binary).
- Use that stage1 binary to build stage2.
- Compare behavior and (best-effort) emitted `.ml` output hashes.

Run:

```bash
npm run test:upstream:stage2
```

### Gate 3 (runci matrix for selected targets)

Gate 3 runs additional upstream `tests/runci` targets beyond `Macro`.

Select targets via `HXHX_GATE3_TARGETS` (comma-separated) or pass them as args:

```bash
HXHX_GATE3_TARGETS="Macro,Js,Neko" npm run test:upstream:runci-targets
```

Run a lightweight JS runtime oracle comparison (upstream `haxe` vs linked `hxhx --js <file>`):

```bash
npm run test:upstream:js-oracle-smoke
```

Notes:

- This uses repo-local fixtures and compares runtime behavior (stdout + exit code) by compiling each fixture with both compilers.
- Default fixture set covers loop arithmetic, switch expressions, enum reflection helpers, try/catch rethrow, array comprehensions, range expressions, `new Array(...)`, and multi-catch dispatch.
- Optional controls:
  - `HXHX_JS_ORACLE_FIXTURES=JsOracleLoopMain,JsOracleTryCatchMain` to run a subset.
  - `HXHX_JS_ORACLE_REQUIRE_HAXE_437=0` to bypass strict `haxe --version` enforcement.
  - `HXHX_FORBID_STAGE0=1` (default in this runner) to block delegation while compiling with `hxhx`.

CI subset reproduction (matches `.github/workflows/ci.yml` `js-native-smoke` job):

```bash
HXHX_JS_ORACLE_FIXTURES=JsOracleLoopMain,JsOracleSwitchExprMain,JsOracleTryCatchMain,JsOracleRangeExprMain,JsOracleNewArrayMain,JsOracleMultiCatchMain \
  npm run test:upstream:js-oracle-smoke
```

Run the linked builtin target smoke (delegated `--ocaml-eval` vs native `--ocaml`):

```bash
npm run test:hxhx:builtin-target-smoke
```

Run the native JS emit+run lane only (no OCaml timing compare):

```bash
HXHX_BUILTIN_SMOKE_OCAML=0 HXHX_BUILTIN_SMOKE_JS_NATIVE=1 npm run test:hxhx:builtin-target-smoke
```

Notes:

- Full delegated-vs-builtin OCaml timing smoke is **not** part of PR/push CI by default (toolchain/runtime cost).
- Gate 3 CI workflow (`.github/workflows/gate3.yml`) runs weekly on Linux with deterministic defaults (`targets=Macro,Js,Neko`, `macro_mode=direct`, `allow_skip=0`).
  It is also manually triggerable with `workflow_dispatch` inputs for `targets`, `allow_skip`, and `macro_mode`.
- Builtin target smoke CI (`.github/workflows/gate3-builtin.yml`) runs on push/PR, weekly schedule, and manual trigger (`reps` only). It now always runs native JS smoke plus full JS oracle fixtures.
- PR/push CI (`.github/workflows/ci.yml`) includes a dedicated native-JS smoke job (`HXHX_BUILTIN_SMOKE_OCAML=0`, `HXHX_BUILTIN_SMOKE_JS_NATIVE=1`) and a JS-oracle subset in the same job.
- PR/push CI also includes dedicated `JS oracle smoke (upstream vs hxhx)` via `.github/workflows/js-oracle-smoke.yml`, which runs the full fixture set.
- By default, missing target toolchains fail the run; set `HXHX_GATE3_ALLOW_SKIP=1` to skip missing deps.
- Flaky-target retry policy defaults to one retry for `Js` (`HXHX_GATE3_RETRY_COUNT=1`, `HXHX_GATE3_RETRY_TARGETS=Js`, `HXHX_GATE3_RETRY_DELAY_SEC=3`); set `HXHX_GATE3_RETRY_COUNT=0` to disable.
- Before Gate 3 resolves packages, builds a compiler, or creates its temporary upstream worktree, `scripts/hxhx/check-local-capacity.js` prints `HXHX_LOCAL_CAPACITY:<PASS|WARNING|BLOCKED|OFF>`. With the default `HXHX_HEAVY_RUN_CAPACITY_POLICY=auto`, sustained saturation stops a local run with retryable exit code `75`, while CI records a warning and continues. Use `require` to enforce the check everywhere, `warn` to observe it without stopping, or `off` to deliberately accept the slowdown. `HXHX_HEAVY_RUN_MAX_LOAD_PER_CPU` changes only the capacity threshold, and `HXHX_HEAVY_RUN_CAPACITY_REPORT=/path/report.json` retains a redacted JSON report. These controls never change targets, retries, timeouts, stage0 rules, or pass criteria.
- Long-run observability/guardrails: `HXHX_GATE3_TARGET_HEARTBEAT_SEC=20` prints periodic progress (set `0` to disable) and `HXHX_GATE3_TARGET_TIMEOUT_SEC=0` controls the default per-target timeout (set a non-zero value to fail hard hangs). Use `HXHX_GATE3_TARGET_TIMEOUT_<TARGET>_SEC` for a target-specific override, for example `HXHX_GATE3_TARGET_TIMEOUT_CPP_SEC=5400` in the strict extended Cpp burn-down lane. When a target attempt times out, the runner stops the attempt process tree so stale child processes cannot keep mutating the result. The weekly CI baseline sets `HXHX_GATE3_TARGET_TIMEOUT_SEC=4200`.
- Treat the attached command output as the source of truth for long local Gate 3 runs. Each target attempt now prints `gate3_target_attempt_start`, periodic `gate3_target_heartbeat` lines, and `gate3_target_attempt_end status=<pass|fail|timeout> exit=<code> elapsed=<sec>s`; do not infer completion from stale `ps` polling alone.
- To force a fresh full-profile current-source compiler instead of the committed bootstrap snapshot, run `npm run -s hxhx:build-current-source`, then `source packages/hxhx/out/hxhx-current-source.env` and pass `HXHX_REQUIRE_CURRENT_SOURCE_BIN=1 HXHX_BIN="$HXHX_BIN"` to the Gate 3 command. The faster `hxhx:current-source-bin:fast` profile is intentionally rejected by this proof lane.
- On macOS, the upstream `Js` server stage remains enabled, but Gate 3 relaxes async timeouts (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000` by default). Set `HXHX_GATE3_FORCE_JS_SERVER=1` to run without timeout patches (debug mode).
- Python target runs default to no-install mode (`HXHX_GATE3_PYTHON_ALLOW_INSTALL=0`): both `python3` and `pypy3` must already be on `PATH`. Set `HXHX_GATE3_PYTHON_ALLOW_INSTALL=1` to allow upstream installer/network fallback.
- Java is validated as an opt-in Gate3 target (`HXHX_GATE3_TARGETS=Java`), including the forced sys-suite lane (`HXHX_RUNCi_FORCE_SYS=1`), and intentionally kept out of the default set (`Macro,Js,Neko`) to keep routine runs faster.
- `HXHX_GATE3_MACRO_MODE` controls how Gate 3 executes the `Macro` target:
  - `direct` (default): route `Macro` through the non-delegating Gate 2 direct runner (`--hxhx-stage3 --hxhx-no-emit`).
  - `stage0_shim`: use the historical stage0 RunCi harness path.
- For the `Macro` target, the runner applies the same stability knobs as Gate 2:
  - `HXHX_GATE2_SKIP_PARTY=1` (default) skips `tests/party` (network-heavy).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`
    seed the local `.haxelib` repo from globally installed libs to avoid network installs when possible.

### M7 replacement-ready bundle

Use one command to run a curated replacement-readiness bundle with a clear PASS/FAIL summary:

```bash
npm run test:upstream:replacement-ready
```

Important: this bundle serves two different claim scopes:

- Oracle replacement-ready scope (broad compatibility):
  - `docs/02-user-guide/compat/scoped-1.0-targets.json`
- Native stage0-forbidden scope (strict non-delegating runtime):
  - `docs/02-user-guide/compat/native-scope-targets.json`
  - selected by default when strict mode is enabled (`HXHX_M7_STRICT=1`)

Profiles:

- `fast` (default): `ci:guards`, `test:hxhx-targets`, focused Gate2 display rung, builtin target smoke.
- `full`: includes `fast` plus Gate1 unit-macro, Gate2 runci Macro, and Gate3 runci targets.
  - In strict mode (`HXHX_M7_STRICT=1`), full profile also enables plugin matrix checks by default
    (`HXHX_M7_REQUIRE_PLUGIN_MATRIX=1`).
  - Host-aware default for Gate3 targets in this bundle: Linux=`Macro,Js,Neko`, macOS=`Macro,Neko` (override with `HXHX_GATE3_TARGETS=...`).

Examples:

```bash
# Full bundle
HXHX_M7_PROFILE=full npm run test:upstream:replacement-ready

# Full bundle, strict mode (fails on skipped upstream checks)
HXHX_M7_PROFILE=full HXHX_M7_STRICT=1 npm run test:upstream:replacement-ready

# Full bundle, strict + stage0-forbidden runtime guard
npm run test:upstream:replacement-ready:strict
```

Claim mapping:

- Use `npm run test:upstream:replacement-ready` for oracle replacement-ready statements.
- Use `npm run test:upstream:replacement-ready:strict` for stage0-forbidden native-scope statements.
- Override scope manifest explicitly with `HXHX_M7_SCOPE_FILE=/path/to/scope.json` when needed.

CI cadence:

- `.github/workflows/gate-m7.yml` runs weekly on Linux in strict/full mode (`HXHX_M7_PROFILE=full`, `HXHX_M7_STRICT=1`).
- The same workflow also runs on published releases in strict/full mode.
- The same workflow remains manually triggerable (`workflow_dispatch`) with `profile` and `strict` inputs.

## Layers

### 1) “Build the backend” checks (fast, no dune required)

These checks run `haxe` compilations and/or compare emitted `.ml` text:

- **Printer tests**: ensure OCaml AST printing stays stable/valid.
- **Integration compile tests**: ensure the backend can compile representative Haxe code.
- **Snapshot tests** (`test/snapshot/**`): golden `.ml` output comparisons (compile-to-OCaml only; no dune build).

These catch regressions in:

- TypedExpr lowering (`OcamlBuilder`)
- printing/formatting (`OcamlASTPrinter`)
- module scheduling/ordering (`OcamlCompiler`)

### 2) “Runs under dune” checks (requires OCaml toolchain)

If `dune` and `ocamlc` are available, we additionally run:

- **Portable fixtures** (`test/portable/fixtures/**`): compile → dune build → run → diff stdout.
- **Examples** (both roots): compile → dune build → run → diff stdout.
  - `examples/**`
  - `packages/reflaxe.ocaml/examples/**`

`EXAMPLE_COVERAGE_CONTRACT:PASS` is emitted by `npm run guard:example-coverage`.
That guard inventories both example roots and fails if a buildable example has no
`expected.stdout`, no README, or is not wired into the documented example runner
contract.

The intended split is:

- normal buildable examples: `npm run test:examples`
- heavier or host-tool-dependent examples: `npm run test:acceptance`
- non-`build.hxml` fixtures: a dedicated command documented in the fixture README

Every example should prove what the compiler alone cannot prove. For pure compile
smokes, this can be a tiny `expected.stdout`; for behavior examples, assert the
observable runtime result in stdout so CI catches stale examples after compiler or
runtime changes. If an example needs checks beyond stdout, add `test.hxml` or
`test.sh`; `scripts/test-examples.sh` runs those example-specific checks after the
compile/build/run/stdout-diff step.

Do not snapshot every example's generated output by default. The normal example
contract is stronger for user-facing confidence: compile the example, build the
artifact, run it, and compare behavior. Add targeted snapshots only when generated
code shape is itself the contract, when runtime output cannot expose the bug, or
when a compiler/lowering seam needs a stable golden artifact.

These catch regressions that pure snapshot tests can’t, like:

- OCaml type errors caused by ordering/dependencies
- missing runtime shims or incorrect OCaml stdlib usage
- runtime-level behavioral differences (null semantics, string handling, sys APIs)

### 3) Acceptance workloads (explicitly heavier)

`npm run test:acceptance` runs two heavier layers:

- acceptance-only examples under:
  - `examples/`
  - `packages/reflaxe.ocaml/examples/`
  (flagged with `ACCEPTANCE_ONLY`)
- compiler-shaped workloads under `workloads/`

Current workload set:

- `workloads/hih-workload` — Stage 1 multi-file "project compiler" workload
- `workloads/hih-compiler` — Stage 2/3 compiler-skeleton workload (marked heavy)

Profiles:

- `fast` (default): runs non-heavy workloads only
- `full`: runs all workloads, including heavy compiler-shaped ones

Commands:

```bash
# default acceptance path (developer-friendly)
npm run test:acceptance

# full acceptance path (includes heavy workloads)
npm run test:acceptance:full

# workload layer only (fast profile by default)
npm run test:workloads

# run only the heavy compiler workload explicitly
WORKLOAD_PROFILE=full WORKLOAD_FILTER=hih-compiler npm run test:workloads
```

Runtime controls (`scripts/test-workloads.sh`):

- `WORKLOAD_PROGRESS_INTERVAL_SEC` (default `20`) prints heartbeat lines during long compile steps
- `WORKLOAD_HEAVY_TIMEOUT_SEC` (default `600`) compile timeout budget for workloads marked with `HEAVY_WORKLOAD`
- `WORKLOAD_TIMEOUT_SEC` overrides compile timeout budget for all workloads (`0` disables timeout)
- `WORKLOAD_FILTER=<substring>` runs matching workloads only

Runtime baseline output:

- each workload prints `timing: compile=<sec> run=<sec> total=<sec>`
- the script ends with a global summary line including profile, run/skipped counts, and total seconds
