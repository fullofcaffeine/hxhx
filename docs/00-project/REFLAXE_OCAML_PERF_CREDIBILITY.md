# reflaxe.ocaml Target Performance Credibility

Last audited: 2026-07-19

This page defines the target-level performance evidence lane for `reflaxe.ocaml` as a standalone OCaml target.

Canonical contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`

Machine-readable baseline:

- `docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json`

Deterministic runner and hosted workflow:

- `scripts/ci/run-reflaxe-ocaml-perf.js`
- `scripts/ci/run-reflaxe-ocaml-iteration-perf.js`
- `.github/workflows/reflaxe-ocaml-package-matrix.yml`

Success markers:

- `RO_TARGET_PERF_CREDIBLE:PASS`: local reference-host regression gate
- `RO_TARGET_ITERATION_REPORT:PASS`: focused cold/warm/one-file report
- `RO_TARGET_PERF_PLATFORM:PASS`: one installed-package host receipt
- `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`: artifact-opened Linux and macOS aggregate

Primary artifacts:

- `.artifacts/reflaxe-ocaml/perf/summary.json`
- `.artifacts/reflaxe-ocaml/iteration-perf/summary.json`
- CI artifact `reflaxe-ocaml-perf-<host>-<commit>` for each host receipt
- CI artifact `reflaxe-ocaml-perf-matrix-<commit>` for the verified aggregate

## Goal

Show that `reflaxe.ocaml` has a credible target-level performance story on its own:

- upstream `haxe 4.3.7` can drive native OCaml builds in a stable time envelope,
- a copied project records the standalone target's cold-output, unchanged-warm,
  and one-Haxe-file authoring loops without modifying tracked source,
- emitted OCaml/native artifacts stay in a bounded size envelope for representative workloads,
- the `metal` profile does not collapse into an obviously worse runtime lane than `portable` on a simple hot-loop benchmark,
- and the release-shaped ZIP is measured after an isolated install on the same Linux and macOS hosts that prove package behavior.

This is target-product evidence.
It is not the `hxhx Full 1.0` compiler-performance parity gate.

## Measurement method

The local reference-host regression command is:

```bash
node scripts/ci/run-reflaxe-ocaml-perf.js
```

The runner measures two classes of scenario in both modes:

1. Native build throughput on upstream-Haxe validation examples.
2. Native build + runtime hot-loop timing on the deterministic `hxhx-native-reflaxe-bench` fixture.

Method details:

- host compiler is upstream `haxe 4.3.7`
- the hosted lane uses OCaml `5.2.1`, Dune `3.24.0`, and Node `20`
- each build scenario removes the emitted `out/` directory before each rep
- shared compiler/toolchain caches may remain warm; raw samples retain execution order so the first-run cost stays visible
- build timing is measured around the full `haxe ... -D ocaml_build=native` command
- runtime timing uses the built native executable only; compile time and run time are tracked separately
- every build scenario has three raw build samples; each runtime scenario has nine raw execution samples
- artifact size tracking records:
  - emitted `.ml/.mli` byte volume
  - emitted `.ml/.mli` file count
  - final native executable size
- all four normal examples execute and match their checked `expected.stdout`
- benchmark output is verified against a deterministic computed result for every accepted runtime sample

### Standalone authoring-iteration method

The focused command is:

```bash
node scripts/ci/run-reflaxe-ocaml-iteration-perf.js
```

It copies `packages/reflaxe.ocaml/examples/build-macro` into an isolated
workspace and measures this exact ordered state family:

1. `cold-output`: remove only the copied `out/` directory, then compile and run.
2. `warm-unchanged`: preserve the copied source and output directory, compile
   again, and require zero generated `.ml`/`.mli` content changes.
3. `one-file-change`: replace one exact token in the copied
   `src/BuildMacro.hx`, compile again, require changed generated OCaml, and
   verify the alternate executable output.

One complete state cycle warms the measurement path. The receipt retains that
warmup, but excludes it from the statistics. Three further cycles are retained
in execution order and summarized. The copied Haxe source is restored even if
measurement fails; the checked-in example is never edited.

The names describe output and source state, not the whole machine's cache
state. Shared Haxe, Dune, OCaml, filesystem, and operating-system caches may
remain warm. The method never infers cache hits. It records these boundaries
separately:

- full `haxe` child time, including startup, typing, generation,
  orchestration, and target-owned subprocesses;
- summed target-owned subprocess time from the linked timing receipt;
- time outside those target-owned subprocesses;
- aggregate Dune build time, which includes typechecking, compilation, and
  linking;
- interface-specific target subprocess time; and
- external executable verification time.

It does not claim separate target load, process startup, or workload-runtime
measurements. Those fields remain explicitly false/null until a future method
measures them. Iteration timing uses
`report-only-until-stable-hosted-trend`: it must pass provenance, state,
generated-change, timing-receipt, and executable-behavior checks, but it has no
latency threshold yet.

The hosted lane adds stronger package isolation:

1. One Ubuntu producer builds the deterministic source ZIP and records its clean commit and SHA-256.
2. Ubuntu and macOS consumers install that exact downloaded ZIP into disposable haxelib repositories; they do not rebuild it.
3. The performance runner copies each example to a workspace outside the checkout and proves `haxelib path reflaxe.ocaml` resolves only from the disposable installation.
4. Each host runs the six clean-build scenarios plus the copied authoring
   iteration workload and records raw samples, output hashes, generated-change
   inventories, file sizes, CPU/load/memory facts, runner image metadata,
   toolchain versions, and package provenance without machine-local paths.
5. The `installed-package-platform-v2` receipt requires the iteration workload.
   A v1 receipt cannot be accepted as new iteration evidence.
6. The aggregate opens the producer manifest and both receipts. It rejects mixed commits, packages, hosts, methods, missing samples, bad output, malformed metrics, checkout fallback, or absolute-path leakage before emitting `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`.

The workflow runs for relevant pushes and pull requests, on a weekly schedule,
and by manual dispatch. The evidence-ownership freshness window is 192 hours.
The hosted lane reports each machine independently: it never compares Linux
and macOS absolute times as if the runners had identical hardware or load.

Current hosted validation matrix:

| Workflow host | Recorded architecture | Haxe | OCaml | Dune | Node policy |
| --- | --- | --- | --- | --- | --- |
| `ubuntu-latest` | receipt-defined (`x64` today) | `4.3.7` | `5.2.1` | `3.24.0` | major `20` |
| `macos-latest` | receipt-defined (`arm64` today) | `4.3.7` | `5.2.1` | `3.24.0` | major `20` |

This is a verified evidence matrix, not a declaration that every Linux
distribution, every macOS release, or Windows is supported. A runner-image or
architecture change becomes visible in the next receipt and must be reviewed
before results are compared with an older run.

## Historical exact hosted evidence (pre-iteration v1)

[Workflow run 29643502308](https://github.com/fullofcaffeine/hxhx/actions/runs/29643502308)
passed on clean commit
`f23aa3c41031cc8911d8e2d13d725e33e39cc2cb`. Both hosts installed the same
source-only `reflaxe.ocaml` `0.18.19` ZIP outside the checkout:

This run predates `installed-package-platform-v2`. It is retained as exact
six-scenario host history, but it does **not** satisfy the cold/warm/one-file
iteration contract and must not be cited as v2 iteration evidence.

- package SHA-256: `3cc9d4c875bea61bde0dd4b2d729f56997f1a00d1a1aaf430b3652231c59ce18`
- package manifest SHA-256: `e21c267c6e5285e8876272ddc57509f0c468d38142d26a733f1d5cfc5a830466`
- package size and inventory: `310420` bytes and `138` files
- aggregate artifact: `8429363676`
- Linux receipt artifact: `8429359574`
- macOS receipt artifact: `8429361387`

The Linux receipt came from an Ubuntu 24 x64 runner with four virtual
AMD EPYC 7763 CPUs. Its medians were:

| ID | Scenario | Median build | Median run |
| --- | --- | ---: | ---: |
| `ro-perf-01` | `build-macro` | `2258ms` | n/a |
| `ro-perf-02` | `file-io` | `2458ms` | n/a |
| `ro-perf-03` | `ocaml-native-collections` | `2440ms` | n/a |
| `ro-perf-04` | `loop-control` | `2311ms` | n/a |
| `ro-perf-05` | portable benchmark | `2329ms` | `19ms` |
| `ro-perf-06` | metal benchmark | `2118ms` | `19ms` |

On that host, the metal build median was `91%` of portable and its runtime
median was `100%` of portable.

The macOS receipt came from a macOS 26 arm64 runner with three virtual Apple M1
CPUs. Its medians were:

| ID | Scenario | Median build | Median run |
| --- | --- | ---: | ---: |
| `ro-perf-01` | `build-macro` | `2994ms` | n/a |
| `ro-perf-02` | `file-io` | `3493ms` | n/a |
| `ro-perf-03` | `ocaml-native-collections` | `3882ms` | n/a |
| `ro-perf-04` | `loop-control` | `3242ms` | n/a |
| `ro-perf-05` | portable benchmark | `3435ms` | `17ms` |
| `ro-perf-06` | metal benchmark | `2566ms` | `16ms` |

On that host, the metal build median was `75%` of portable and its runtime
median was `94%` of portable.

Both receipts used Haxe `4.3.7`, OCaml `5.2.1`, Dune `3.24.0`, and Node
`20.20.2`. All six scenarios passed on both hosts, including expected-output
checks. The artifacts retain the raw samples, generated-source sizes, native
executable sizes, host load, memory, runner image, and output hashes. These are
per-host observations; the Linux and macOS absolute times must not be ranked
against each other. The hosted comparisons against the local reference table
remain informational and are not threshold-enforced.

Reference host used for the current baseline:

- platform: `darwin-arm64`
- CPUs: `12`
- Haxe: `4.3.7`
- dune: `3.21.0`
- ocamlc: `5.4.0`

## Current baseline

The table below remains the local `darwin-arm64` regression reference. It is
not silently promoted into a Linux or hosted-macOS performance budget. Hosted
results live in the per-host and aggregate CI artifacts described above; the
latest exact run and its per-host medians are recorded in the evidence section
after the workflow has completed.

### Native build throughput

| ID | Example | Median native build | Emitted ML bytes | Native exe bytes |
| --- | --- | ---: | ---: | ---: |
| `ro-perf-01` | `build-macro` | `1606ms` | `600860` | `1876600` |
| `ro-perf-02` | `file-io` | `1712ms` | `645352` | `2039864` |
| `ro-perf-03` | `ocaml-native-collections` | `1753ms` | `615061` | `1939880` |
| `ro-perf-04` | `loop-control` | `1673ms` | `603756` | `1876584` |

### Runtime hot-loop profile comparison

Fixture:

- `packages/reflaxe.ocaml/examples/hxhx-native-reflaxe-bench`
- iterations: `200000`

| ID | Profile | Median build | Median run | Emitted ML bytes | Native exe bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| `ro-perf-05` | `portable` | `1683ms` | `14ms` | `605286` | `1942760` |
| `ro-perf-06` | `metal` | `1519ms` | `15ms` | `501632` | `1942760` |

Profile ratios on the reference host:

- `metal` build median: `90%` of portable
- `metal` run median: `107%` of portable

Interpretation:

- default portable builds on representative standalone examples stay around `1.6s` to `1.8s` on the reference host
- the deterministic hot-loop fixture shows `metal` reducing emitted ML volume materially while staying close to portable runtime
- neither profile shows pathological native-executable bloat on the declared standalone scope

## Regression policy

This lane is intentionally bounded, not overfit.

Allowed regression windows in the machine-readable baseline:

- build median: up to `75%` slower than the reference baseline
- emitted ML bytes: up to `25%` larger than the reference baseline
- native executable bytes: up to `25%` larger than the reference baseline
- runtime median on the hot-loop fixture: up to `100%` slower than the reference baseline
- `metal` vs `portable` ratio drift:
  - build median ratio may regress by up to `35%`
  - runtime median ratio may regress by up to `35%`

Those windows are wide on purpose:

- they are meant to catch credibility-damaging regressions,
- not to create a noisy CI gate from small workstation variance.

If a scenario crosses its bound, track it explicitly as a performance regression bead instead of hand-waving it as local variance.

The saved windows are enforced only by `RO_TARGET_PERF_CREDIBLE:PASS` on the
reference-host mode. Hosted `RO_TARGET_PERF_PLATFORM:PASS` receipts record the
same comparisons for context, but pass on package provenance, method integrity,
successful builds, verified behavior, complete raw samples, and valid metrics.
Several repeated runs on a stable hosted machine class are required before a
reviewed hosted threshold can replace report-only evidence.

The authoring-iteration workload is also report-only. Do not derive a threshold
from a busy local run or reinterpret the established clean-build limits as
iteration limits. A future threshold needs repeated, same-method hosted trends
and a reviewed update to the machine-readable contract.

## Known tradeoffs

- The March table is a local reference-host baseline, not a cross-platform guarantee.
- Hosted runner timing can move when GitHub changes hardware, images, load, or cache state; the receipt records those facts instead of hiding them.
- `cold-output` is not a cold machine or cold toolchain claim; it means only
  that the isolated output directory was removed.
- The current iteration method does not split load, startup, and workload
  runtime, and it never guesses cache hits from elapsed time.
- Linux and macOS numbers must be interpreted per host, not ranked against each other.
- Runtime microbench numbers are small enough that OS noise exists; that is why the runtime window is looser than build-size windows.
- The standalone target perf story is intentionally separate from:
  - `hxhx` compiler throughput,
  - `Full 1.0` upstream-relative performance parity,
  - and promotion/plugin runtime startup comparisons.

## Rule

Do not use this document to claim `hxhx` compiler-performance equivalence.
Use it only for the standalone `reflaxe.ocaml` target-product story.

It also does not prove native plugin startup, stock-Haxe/`hxhx` plugin ABI
compatibility, or builtin-target performance. Those are separate promotion and
compiler-product lanes. The intended plugin product still has one semantic ABI
and payload for both hosts; different thin loader shells require a measured
OCaml compiler/runtime/linker/loader incompatibility and may not contain target
semantics.
