# Reflaxe Promotion Matrix Tradeoffs

Last audited: 2026-04-14

This page compares the supported promotion paths named by
`docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`.

Aggregate status: not claimable yet.

Reason: the current tree has an official hxhx plugin-hosted Reflaxe.elixir
native pilot and an upstream-host plugin proof script, but the hxhx built-in
external Reflaxe compiler proof is still explicitly blocked. Until that built-in
proof emits `RPMX_HXHX_BUILTIN:PASS`, this repo must not emit or claim
`RO_PROMOTION_MATRIX:PASS`.

## Evidence Status

| Path | Script | Current marker | Status |
| --- | --- | --- | --- |
| `haxe + reflaxe.ocaml -> plugin` | `npm run test:rpmx:haxe-plugin` | `RPMX_HAXE_PLUGIN:PASS` | Runnable proof script exists. |
| `hxhx + reflaxe.ocaml -> built-in target` | `npm run test:rpmx:hxhx-builtin` | `RPMX_HXHX_BUILTIN:BLOCKED` | No runnable external Reflaxe compiler built-in proof in current tree. |
| `hxhx + reflaxe.ocaml -> plugin` | `npm run test:rpmx:hxhx-plugin` | `RPMX_HXHX_PLUGIN:PASS` | Wrapper over the pinned Reflaxe.elixir native promotion pilot. |

## Same Workload Family

The pressure-test family is Reflaxe.elixir:

- Upstream plugin proof uses the external Reflaxe.elixir generator source path.
- hxhx plugin proof uses the pinned Reflaxe.elixir todo-app promotion pilot.
- hxhx built-in proof is intentionally blocked until the native built-in path can
  exercise an external Reflaxe compiler without pretending plugin evidence is a
  built-in result.

## Tradeoff Summary

| Dimension | Upstream Haxe Plugin | hxhx Plugin Host Adapter | hxhx Built-in |
| --- | --- | --- | --- |
| Startup cost | Uses upstream Haxe startup and eval/plugin loading. | Adds hxhx startup plus native plugin manifest and dynlink setup. | Expected lowest runtime loading overhead once linked, but unproven for external Reflaxe.elixir. |
| Steady-state throughput | Depends on upstream Haxe plus generated OCaml build cost. | Depends on hxhx native lane plus plugin ABI overhead. | Expected best deployment/runtime simplicity for in-tree backends. |
| Native build/runtime cost | Builds OCaml plugin artifacts through dune. | Builds native plugin artifacts and then compiles through hxhx. | Would avoid runtime dynlink, but requires tighter distribution integration. |
| Debugging ergonomics | Easiest baseline because upstream Haxe behavior is familiar. | Best current external native path because artifacts, manifest, and source pin are explicit. | Hardest until the built-in proof exists; failures can blur packaging and compiler routing. |
| Deployment complexity | Requires upstream Haxe and OCaml toolchain alignment. | Requires hxhx, plugin manifest, plugin artifact, and OCaml ABI compatibility. | Requires shipping a rebuilt hxhx distribution. |
| Host coupling | Coupled to upstream Haxe behavior and eval plugin ABI. | Coupled to hxhx native plugin ABI and OCaml dynlink compatibility. | Coupled to hxhx release engineering and target-core ownership. |

## Where Each Path Loses

`haxe + reflaxe.ocaml -> plugin` loses when the goal is proving non-delegating
native hxhx behavior. It is a compatibility and baseline lane, not hxhx native
evidence.

`hxhx + reflaxe.ocaml -> plugin` loses on operational simplicity. The plugin
artifact, manifest, OCaml ABI, and host binary must line up.

`hxhx + reflaxe.ocaml -> built-in target` loses today because the external
Reflaxe.elixir compiler proof is not implemented. It should not be recommended
as the external compiler default until the blocked proof turns into a real pass.

## Recommended Defaults

For external Reflaxe compilers, use the hxhx plugin-hosted promotion path as the
official external native path today.

For upstream compatibility and baseline behavior, use upstream
`haxe + reflaxe.ocaml`.

For built-in distribution work, use the built-in path only for backends already
owned by the hxhx distribution, such as the current linked JS/OCaml target cores.
Do not use it to claim Reflaxe.elixir external native promotion until
`RPMX_HXHX_BUILTIN:PASS` exists.

## Closure Rule

`RO_PROMOTION_MATRIX:PASS` is valid only after all of these are true:

- `RPMX_HAXE_PLUGIN:PASS` was produced by a current proof run.
- `RPMX_HXHX_PLUGIN:PASS` was produced by a current proof run.
- `RPMX_HXHX_BUILTIN:PASS` was produced by a current proof run.
- This tradeoff page is updated with current artifact references and measured
  timings.
- `docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md` points at the
  same current evidence.
