# Reflaxe Promotion Matrix Tradeoffs

Last audited: 2026-04-18

This page compares the supported promotion paths named by
`docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`.

Aggregate status: current evidence satisfies `RO_PROMOTION_MATRIX:PASS` for the
promotion-matrix decision contract.

Scope: this is Reflaxe promotion-path evidence for the pinned Reflaxe.elixir
workload family. It is not a standalone `reflaxe.ocaml` 1.0 claim and it is not
a strict `hxhx` Haxe 4.3.7-equivalence claim.

## Evidence Status

| Path | Script | Current marker | Status |
| --- | --- | --- | --- |
| `haxe + reflaxe.ocaml -> plugin` | `npm run test:rpmx:haxe-plugin` | `RPMX_HAXE_PLUGIN:PASS` | Current timed artifact: `.artifacts/rpmx/haxe-plugin/20260418-060631/rpmx-haxe-plugin.summary.json`. |
| `hxhx + reflaxe.ocaml -> built-in target` | `npm run test:rpmx:hxhx-builtin` | `RPMX_HXHX_BUILTIN:PASS` | Current timed artifact: `.artifacts/rpmx/hxhx-builtin/20260418-120644/rpmx-hxhx-builtin.summary.json`. |
| `hxhx + reflaxe.ocaml -> plugin` | `npm run test:rpmx:hxhx-plugin` | `RPMX_HXHX_PLUGIN:PASS` | Current timed artifact: `.artifacts/rpmx/hxhx-plugin/20260418-060711/rpmx-hxhx-plugin.summary.json`. |

## Same Workload Family

The pressure-test family is Reflaxe.elixir:

- Upstream plugin proof builds the external Reflaxe.elixir generator source path.
- hxhx plugin proof runs the pinned Reflaxe.elixir todo-app promotion pilot.
- hxhx built-in proof compiles and native-builds the pinned Reflaxe.elixir
  `Run` compiler entrypoint through the built-in `--ocaml` path.
- All current proof runs use Reflaxe.elixir commit
  `5b322236e0627f8322394e819cf28ba6c1271a83`.

The commands are not byte-for-byte identical because the paths prove different
host contracts, but they exercise the same real Reflaxe.elixir compiler family
instead of unrelated toy fixtures.

## Current Measured Evidence

The timings below are wall-clock seconds emitted by the proof summaries on
2026-04-18. The hxhx built-in and hxhx plugin runs reused a prebuilt hxhx
bytecode binary so the table compares proof-path work, not compiler bootstrap
time.

| Path | Workload | Total | Main compile/build phase | Runtime/load phase | Artifact |
| --- | --- | ---: | ---: | ---: | --- |
| `haxe + reflaxe.ocaml -> plugin` | `reflaxe-elixir-run-generator` | 3.969s | 1.462s Haxe compile, 0.611s dune build | 0.599s eval load probe, skipped host ABI load | `.artifacts/rpmx/haxe-plugin/20260418-060631/` |
| `hxhx + reflaxe.ocaml -> built-in target` | `reflaxe-elixir-compiler-run-entrypoint` | 17.365s | 17.137s hxhx Stage3 compile/native build | 0.064s artifact copy/hash | `.artifacts/rpmx/hxhx-builtin/20260418-120644/` |
| `hxhx + reflaxe.ocaml -> plugin` | `reflaxe-elixir-todo-promotion-pilot` | 3.911s | 0.265s plugin promotion, 2.281s hxhx compile | 0.044s generated Node run | `.artifacts/rpmx/hxhx-plugin/20260418-060711/` |

## Tradeoff Summary

| Dimension | Upstream Haxe Plugin | hxhx Plugin Host Adapter | hxhx Built-in |
| --- | --- | --- | --- |
| Startup cost | Uses upstream Haxe startup and eval/plugin loading. Current proof total: 3.969s. | Adds hxhx startup plus native plugin manifest and dynlink setup. Current proof total: 3.911s with reused hxhx bytecode. | No runtime dynlink once linked, but current proof has the heaviest compile/native-build path at 17.365s with reused hxhx bytecode. |
| Steady-state throughput | Depends on upstream Haxe plus generated OCaml build cost. | Depends on hxhx native lane plus plugin ABI overhead. | Best deployment/runtime simplicity for in-tree backends, but current compile/native-build cost is higher on this workload. |
| Native build/runtime cost | Builds OCaml plugin artifacts through dune. | Builds native plugin artifacts and then compiles through hxhx. | Would avoid runtime dynlink, but requires tighter distribution integration. |
| Debugging ergonomics | Easiest baseline because upstream Haxe behavior is familiar. | Best current external native path because artifacts, manifest, and source pin are explicit. | Harder than plugin mode because failures can blur packaging and compiler routing inside one hxhx distribution. |
| Deployment complexity | Requires upstream Haxe and OCaml toolchain alignment. | Requires hxhx, plugin manifest, plugin artifact, and OCaml ABI compatibility. | Requires shipping a rebuilt hxhx distribution. |
| Host coupling | Coupled to upstream Haxe behavior and eval plugin ABI. | Coupled to hxhx native plugin ABI and OCaml dynlink compatibility. | Coupled to hxhx release engineering and target-core ownership. |

## Where Each Path Loses

`haxe + reflaxe.ocaml -> plugin` loses when the goal is proving non-delegating
native hxhx behavior. It is a compatibility and baseline lane, not hxhx native
evidence.

`hxhx + reflaxe.ocaml -> plugin` loses on operational simplicity. The plugin
artifact, manifest, OCaml ABI, and host binary must line up.

`hxhx + reflaxe.ocaml -> built-in target` loses when operational decoupling or
iteration speed is more important than packaging simplicity. The proof now
builds a native Reflaxe.elixir compiler entrypoint, but the path still couples
backend promotion to the hxhx distribution instead of a separately shipped
plugin artifact and is currently slower for this measured compile/native-build
proof.

## Recommended Defaults

For external Reflaxe compilers, use the hxhx plugin-hosted promotion path as the
default external native path when independent artifact rollout matters.

For upstream compatibility and baseline behavior, use upstream
`haxe + reflaxe.ocaml`.

For built-in distribution work, use the built-in path when no plugin artifact is
desired and the tighter hxhx release coupling is acceptable. The current
`RPMX_HXHX_BUILTIN:PASS` marker proves compile/native-build viability for the
pinned Reflaxe.elixir compiler entrypoint; it does not by itself prove every
Reflaxe.elixir generated-target runtime scenario.

Current aggregate marker for this evidence window:

```text
RO_PROMOTION_MATRIX:PASS
```

## Closure Rule

`RO_PROMOTION_MATRIX:PASS` is valid only after all of these are true:

- `RPMX_HAXE_PLUGIN:PASS` was produced by a current proof run.
- `RPMX_HXHX_PLUGIN:PASS` was produced by a current proof run.
- `RPMX_HXHX_BUILTIN:PASS` was produced by a current proof run.
- This tradeoff page is updated with current artifact references and measured
  timings.
- `docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md` points at the
  same current evidence.
