# reflaxe.ocaml Target Performance Credibility

Last audited: 2026-03-13

This page defines the target-level performance evidence lane for `reflaxe.ocaml` as a standalone OCaml target.

Canonical contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`

Machine-readable baseline:

- `docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json`

Deterministic runner:

- `scripts/ci/run-reflaxe-ocaml-perf.js`

Success marker:

- `RO_TARGET_PERF_CREDIBLE:PASS`

Primary artifact:

- `.artifacts/reflaxe-ocaml/perf/summary.json`

## Goal

Show that `reflaxe.ocaml` has a credible target-level performance story on its own:

- upstream `haxe 4.3.7` can drive native OCaml builds in a stable time envelope,
- emitted OCaml/native artifacts stay in a bounded size envelope for representative workloads,
- and the `metal` profile does not collapse into an obviously worse runtime lane than `portable` on a simple hot-loop benchmark.

This is target-product evidence.
It is not the `hxhx Full 1.0` compiler-performance parity gate.

## Measurement method

From repo root:

```bash
node scripts/ci/run-reflaxe-ocaml-perf.js
```

The runner measures two classes of scenario:

1. Native build throughput on upstream-Haxe validation examples.
2. Native build + runtime hot-loop timing on the deterministic `hxhx-native-reflaxe-bench` fixture.

Method details:

- host compiler is upstream `haxe 4.3.7`
- each build scenario removes the emitted `out/` directory before each rep
- build timing is measured around the full `haxe ... -D ocaml_build=native` command
- runtime timing uses the built native executable only; compile time and run time are tracked separately
- artifact size tracking records:
  - emitted `.ml/.mli` byte volume
  - emitted `.ml/.mli` file count
  - final native executable size
- benchmark output is verified against a deterministic expected result before runtime timings are accepted

Reference host used for the current baseline:

- platform: `darwin-arm64`
- CPUs: `12`
- Haxe: `4.3.7`
- dune: `3.21.0`
- ocamlc: `5.4.0`

## Current baseline

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

## Known tradeoffs

- This is a local reference-host baseline, not a cross-platform guarantee.
- Runtime microbench numbers are small enough that OS noise exists; that is why the runtime window is looser than build-size windows.
- The standalone target perf story is intentionally separate from:
  - `hxhx` compiler throughput,
  - `Full 1.0` upstream-relative performance parity,
  - and promotion/plugin runtime startup comparisons.

## Rule

Do not use this document to claim `hxhx` compiler-performance equivalence.
Use it only for the standalone `reflaxe.ocaml` target-product story.
