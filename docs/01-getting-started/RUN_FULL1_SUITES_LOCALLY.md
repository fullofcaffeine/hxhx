# Run Full1 Suites Locally

Last audited: 2026-03-05

This page explains how to run the Full 1.0 suite runners that were added for strict parity closure work.

## What These Runners Do

The suite runner:

- uses `hxhx` as the compiler command,
- forces strict mode (`HXHX_FORBID_STAGE0=1`) by default,
- writes deterministic artifacts under `.artifacts/full1/suites/`,
- emits a suite marker on success.

Current markers:

- `FULL1_SUITE_MISC:PASS`
- `FULL1_SUITE_SERVER:PASS`
- `FULL1_SUITE_THREADS:PASS`
- `FULL1_SUITE_OPTIMIZATION:PASS`
- `FULL1_SUITE_DISPLAY:PASS`

## Prerequisites

- Upstream checkout is available at `vendor/haxe` (untracked).
- Toolchains needed by the selected suite are installed.
- From repo root, install JS deps: `npm ci`.

## Run One Suite

```bash
npm run -s test:full1:suite:misc
npm run -s test:full1:suite:server
npm run -s test:full1:suite:threads
npm run -s test:full1:suite:optimization
npm run -s test:full1:suite:display
```

Each command writes:

- `.artifacts/full1/suites/<suite>.log`
- `.artifacts/full1/suites/<suite>.summary.json`

## Run All Current Full1 Suite Runners

```bash
npm run -s test:full1:suites:strict
```

## Monitor Long Local Runs

Use one attached terminal/session per heavy local gate and treat that output as
the source of truth. Do not decide that a run is finished from stale `ps`
polling alone.

Useful markers:

- Gate 3 target attempts print `gate3_target_attempt_start`,
  `gate3_target_heartbeat`, and `gate3_target_attempt_end status=<pass|fail|timeout> exit=<code> elapsed=<sec>s`.
- Gate 2 Stage3 emit-runner attempts print `gate2_stage3_emit_runner_start`,
  `gate2_stage3_emit_runner_heartbeat`, and `gate2_stage3_emit_runner_end status=<pass|fail|timeout> exit=<code> elapsed=<sec>s`.

## Build A Fresh Current-Source `HXHX_BIN`

Use this when a Full1 blocker might be fixed in source but not yet reflected in
the committed bootstrap snapshot:

```bash
npm run -s hxhx:build-current-source
source packages/hxhx/out/hxhx-current-source.env
HXHX_REQUIRE_CURRENT_SOURCE_BIN=1 HXHX_BIN="$HXHX_BIN" \
  HXHX_GATE3_TARGETS=Js npm run -s test:upstream:runci-targets
```

What this loop guarantees:

- `hxhx:build-current-source` forces `HXHX_FORCE_STAGE0=1`, so the binary is
  built from the current source tree rather than the committed bootstrap
  snapshot.
- `packages/hxhx/out/hxhx-current-source.env` records the binary path, git HEAD,
  dirty/clean state, tracked status/content hashes, and build duration.
- `HXHX_REQUIRE_CURRENT_SOURCE_BIN=1` makes Gate2/Gate3 local repro runners fail
  fast if `HXHX_BIN` is missing provenance metadata, points at a different
  binary, or was built from a different tracked checkout state.
- If you intentionally want to reuse a stale proof binary for diagnosis only,
  set `HXHX_CURRENT_SOURCE_ALLOW_STALE=1`; do not use stale-binary evidence for
  closure notes.

## Source-Build Probe (Non-Blocking Diagnostic Lane)

Use this when you need to check whether a source-only fix works before bootstrap snapshots catch up.

```bash
npm run -s test:full1:source-probe
```

What it does:

- forces source build (`HXHX_FORCE_STAGE0=1`),
- runs narrowed strict suites (`server`, `optimization`),
- writes artifacts under `.artifacts/full1/source-probe/`,
- keeps `source-probe.summary.json` compact by recording log paths, byte counts, and short stdout/stderr tails while storing full logs separately,
- enforces child-process timeouts (`FULL1_SOURCE_PROBE_BUILD_TIMEOUT_SECS`, default `960`; `FULL1_SOURCE_PROBE_SUITE_TIMEOUT_SECS`, default `600`) so the diagnostic produces `PASS`/`WARN` evidence instead of occupying a runner indefinitely,
- may continue into suite diagnostics if the source build times out after printing a usable `hxhx` binary path; the summary records `build.timed_out=true`, `build.usable_after_timeout=true`, and the overall marker remains `WARN`,
- emits `FULL1_SOURCE_BUILD_PROBE:PASS` or `FULL1_SOURCE_BUILD_PROBE:WARN`.

## Bootstrap-Source Reconciliation (Diagnostic Classification Lane)

Use this when server/optimization blockers might be hidden by bootstrap lag and you need paired evidence on the same commit.

```bash
npm run -s test:full1:bootstrap-source-reconcile
```

What it does:

- builds/runs strict suite checks for `server` + `optimization` in both lanes:
  - bootstrap-built `hxhx`
  - source-built `hxhx` (`HXHX_FORCE_STAGE0=1`)
- writes paired artifacts under `.artifacts/full1/reconciliation/{bootstrap,source}/`,
- writes classification summary `.artifacts/full1/reconciliation/bootstrap-source-reconciliation.summary.json`,
- emits `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:PASS` when blocker classification is complete, otherwise `...:WARN`.
- defaults to bounded timeouts so the diagnostic lane produces evidence instead of running until the workflow-level timeout:
  - `FULL1_RECONCILE_BUILD_TIMEOUT_SECS=900`
  - `FULL1_RECONCILE_SUITE_TIMEOUT_SECS=600`

## Optional Debug Knobs

- Run only one misc project:
  - `MISC_TEST_FILTER=1234 npm run -s test:full1:suite:misc`
- Reuse an already-built `hxhx` binary:
  - `HXHX_BIN=/abs/path/to/hxhx npm run -s test:full1:suite:server`

## Notes

- These runners are part of Full1 gate scaffolding and may fail while parity work is still in progress.
- Failures are expected to be actionable through the suite log and summary artifacts.
- The primary Full1 matrix remains bootstrap-based for stability; source probe is advisory evidence.
