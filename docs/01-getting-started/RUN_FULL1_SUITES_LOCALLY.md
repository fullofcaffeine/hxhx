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

## Optional Debug Knobs

- Run only one misc project:
  - `MISC_TEST_FILTER=1234 npm run -s test:full1:suite:misc`
- Reuse an already-built `hxhx` binary:
  - `HXHX_BIN=/abs/path/to/hxhx npm run -s test:full1:suite:server`

## Notes

- These runners are part of Full1 gate scaffolding and may fail while parity work is still in progress.
- Failures are expected to be actionable through the suite log and summary artifacts.
