# Core Tests critical-path baseline — 2026-07-18

This report records why the required Core Tests check took 45 minutes and the
bounded CI change used to shorten it without removing coverage. It belongs to
Bead `haxe_ocaml-850ii.16`.

## Exact baseline

- Candidate: `5c25fab890d9e19b77e8e03045b52793bb390d02`
- Core workflow run: `29651063170`
- Tests job: `88098521412`
- Tests job wall time: 45m10s, from `2026-07-18T16:12:52Z` through
  `2026-07-18T16:58:02Z`
- Complete workflow wall time: about 58m36s
- Commands in `npm test`: 106

The first npm command started about 2m09s after the job began. The 106 test
commands then consumed 2,577.566 seconds (42m57.566s). The old job ran every
command serially after Guardrails, Stage0-free smoke, JS-native smoke, and the
plugin matrix had all completed.

## Measured command families

The inventory was reconstructed in canonical `npm test` order from the exact
job log. The committed manifest at
`scripts/ci/core-test-shards.json` makes that inventory executable: every
aggregate command must appear exactly once and must name a known shard.

| Clean-runner family | Commands | Baseline test body | Main cost |
| --- | ---: | ---: | --- |
| Compiler and focused regressions | 99 | 4m38.097s | Focused Haxe, OCaml, C++, and JS checks |
| Macro-host integration | 3 | 13m25.742s | Three roughly 4½-minute native macro-host integration builds |
| Portable, snapshots, and examples | 3 | 5m09.205s | Package/runtime builds and executable examples |
| hxhx target end-to-end | 1 | 19m44.522s | The intentionally serialized Stage1/Stage3/plugin end-to-end script |

The five largest individual commands were:

| Command | Baseline |
| --- | ---: |
| `test:hxhx-targets` | 19m44.522s |
| `test:m14:macro-host-runtime-api` | 4m29.057s |
| `test:m14:runtime-build-fields` | 4m28.848s |
| `test:m14:stage3-on-type-not-found` | 4m27.837s |
| `test:portable` | 2m47.718s |

## Parallelization boundary

CI gives each family its own clean checkout, OCaml switch, npm install, Haxe
toolchain, and temporary output tree. No generated compiler, target output, or
mutable build directory crosses between shards. Commands retain their original
relative order inside each family.

The boundaries are deliberately conservative:

- the three macro-host integrations remain serial because they exercise the
  same host build and runtime lifecycle;
- portable fixtures, snapshot validation, and examples retain their order as
  one target/package family;
- `test:hxhx-targets` remains one command because its 2,754-line harness shares
  a built compiler, a stable copied macro host, and many temporary fixtures;
- the cleanup regression is self-contained and stays last in the compiler
  shard;
- every shard waits for Guardrails, avoiding four expensive runners when a
  cheap repository contract has already failed.

The Stage0-free, JS-native, and plugin jobs continue independently. The shards
may run alongside them after Guardrails. A stable job named `Tests` waits for
all of those jobs and the complete shard matrix. It fails when any required
result is failed, cancelled, skipped, or missing.

## Local standalone validation

Each generated shard command passed independently before the workflow change
was pushed:

| Shard | Commands | Local elapsed |
| --- | ---: | ---: |
| Compiler and focused regressions | 99 | 3m43.852s |
| Macro-host integration | 3 | 10m27.444s |
| Portable, snapshots, and examples | 3 | 4m43.029s |
| hxhx target end-to-end | 1 | 25m20.861s |

These local timings prove command ownership and standalone execution, not the
hosted-runner performance claim. The last shard ran during a different host
load window and was slower than the retained exact GitHub baseline, so it is
not substituted into the hosted-runner result below.

## Expected and measured outcome

Before the first exact pushed run, the measured command bodies predicted a
slowest shard around 22 minutes and about 49m25s of total Tests runner time.
The prediction was directionally correct, but clean-runner setup and ordinary
hosted-runner variance made the exact compute cost higher.

The first pushed run used candidate
`56310df380f5094d9e4eac664ec2f03c5de52c90` and passed as Core workflow
`29686414970`. The exact shard results were:

| Shard | Job | Job wall time | Test-step time |
| --- | ---: | ---: | ---: |
| Compiler and focused regressions | `88191637270` | 5m35s | 3m41s |
| Macro-host integration | `88191637241` | 16m32s | 14m09s |
| Portable, snapshots, and examples | `88191637240` | 7m52s | 5m42s |
| hxhx target end-to-end | `88191637232` | 23m08s | 21m11s |
| Fail-closed `Tests` aggregate | `88193644992` | 7s | not applicable |

All four shards, all independent prerequisite jobs, and the aggregate passed.
The earliest shard began at `2026-07-19T12:11:48Z`; the aggregate completed at
`2026-07-19T12:35:09Z`. The workflow itself ran from
`2026-07-19T12:07:51Z` through `2026-07-19T12:35:09Z`.

| Measure | Monolithic baseline | Sharded run | Change |
| --- | ---: | ---: | ---: |
| Summed test-command time | 42m57s | 44m43s | +1m46s (+4.1%) |
| Total Tests runner time | 45m10s | 53m14s | +8m04s (+17.9%) |
| Required Tests critical path | 45m10s | 23m21s | -21m49s (-48.3%) |
| Complete Core workflow | 58m36s | 27m18s | -31m18s (-53.4%) |

The summed command-time difference is normal hosted-runner variance; the
manifest still assigns every one of the same 106 commands exactly once. The
17.9% runner-time increase is the measured cost of isolated checkouts and
toolchain setup. It is accepted because it removes 21m49s from the required
test critical path and 31m18s from the complete workflow without sharing
mutable build artifacts, weakening Stage0 rules, or hiding a failed lane.

## Local workflow

`npm test` remains the canonical complete local command and retains its exact
106-command order. For a focused reproduction of one CI family, use:

```bash
npm run test:ci:shard -- --shard compiler
npm run test:ci:shard -- --shard macro-host-integration
npm run test:ci:shard -- --shard target-packages
npm run test:ci:shard -- --shard hxhx-targets
```

`npm run guard:core-test-shards` checks command coverage, ordering, matrix
wiring, and fail-closed aggregate behavior without running the test bodies.
The local shard command also holds the shared Haxe-family heavy-run lease for
up to 30 minutes before starting; CI bypasses that user-scoped scheduler so its
four clean runners remain parallel.
