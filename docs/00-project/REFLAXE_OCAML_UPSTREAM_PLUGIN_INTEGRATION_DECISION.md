# reflaxe.ocaml Upstream Haxe Native Plugin Integration Decision

Last reviewed: 2026-04-03

This note records the post-1.0 decision for how `reflaxe.ocaml` should integrate with mainstream upstream Haxe when users want plugin-shaped native artifacts.

## Decision

The supported upstream-Haxe integration path remains:

- explicit upstream eval-host adaptation through `eval.vm.Context.loadPlugin`

The following is **not** a supported path today:

- a true upstream compiler-target/native-target plugin path where upstream Haxe exposes a first-class backend/plugin ABI comparable to `hxhx` native backend loading

In short:

- upstream Haxe support means `haxe + reflaxe.ocaml + explicit eval-host adapter`
- it does **not** mean `haxe + reflaxe.ocaml + true native compiler-target plugin`

## Why this decision is correct

### 1. It matches the real upstream host seam that exists today

The documented upstream-host loading contract in this repo is:

- `eval.vm.Context.loadPlugin(pluginPath)`

That is a macro/eval host seam. It is not the same thing as a backend-target plugin ABI.

Current repo contracts already reflect this:

- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`

### 2. It matches the proof we actually have

The proven upstream-host path today is the explicit host-adapter/plugin workflow:

- `RPMX_HAXE_PLUGIN:PASS`

That proof builds a real Reflaxe workload through upstream Haxe and `reflaxe.ocaml`, then records host/compiler/artifact provenance explicitly. It does not claim that upstream Haxe has a true compiler-target plugin surface.

### 3. It keeps the repo honest about ABI and packaging

The upstream host-adapter lane is intentionally Level-1 compatible only:

- workflow/contract compatibility
- no shared cross-host binary ABI claim
- no promise that one `.cmxs` works unchanged across `hxhx` and upstream eval hosts

That boundary is already documented and should remain explicit.

### 4. It preserves MIT clean-room discipline

Claiming a true upstream compiler-target plugin path would require a stable upstream extension boundary and a clean-room implementation plan around it. We do not have that today. Pretending otherwise would create misleading product evidence and provenance risk.

## Compared options

| Option | Status | Why |
| --- | --- | --- |
| Explicit upstream eval-host adapter (`loadPlugin`) | Supported | Real host seam exists, already documented, already has proof lanes, and keeps packaging/ABI claims narrow. |
| True upstream compiler-target/native-target plugin path | Not supported | No repo evidence today that upstream Haxe exposes a stable backend/plugin ABI for this use case. Treat as research only. |

## Supported path: packaging shape and constraints

The supported upstream-host packaging shape is the eval-host adapter lane:

- generated host glue stays separate from reusable target core
- upstream host entrypoint is `plugin/haxe/entry.ml`
- generated upstream-host manifest is `eval-plugin.json`
- manifest kind is `haxe-eval`
- manifest load API is `eval.vm.Context.loadPlugin`
- `crossHostBinaryCompatibility` must remain `false`

Operational constraints:

- host compiler is upstream Haxe `4.3.7`
- OCaml artifact loading is host/toolchain-sensitive
- ABI mismatches between the upstream host and local OCaml toolchain can legitimately fail dynlink loading
- those failures must stay explicit; they are not license/provenance problems and they are not evidence of a hidden compiler-target plugin seam

## Non-goals

These are explicitly out of scope for the upstream-Haxe path today:

- claiming that upstream Haxe has a first-class backend-target plugin ABI
- claiming that one native plugin binary is portable across both upstream Haxe and `hxhx`
- documenting or advertising a new upstream CLI/backend flag that does not exist
- adding semantics or extension behavior that upstream Haxe `4.3.7` does not define
- blurring the supported eval-host adapter lane into a broader “upstream native target plugin” promise

## Release and documentation rule

Public docs must use this wording boundary:

- supported: “upstream Haxe host-adapter path”
- unsupported: “true upstream compiler-target plugin path”

If docs need a short version, use:

- “upstream Haxe supports plugin-shaped reflaxe.ocaml artifacts through the eval-host adapter path”

Do not use:

- “upstream Haxe supports native backend plugins”

That wording is too broad and implies a host/plugin ABI we have not proven.

## Test plan

The supported upstream path should continue to be validated with:

1. upstream-host build/provenance proof
   - `bash scripts/ci/run-rpmx-haxe-plugin-proof.sh`
2. eval-host adapter smoke
   - `bash scripts/hxhx/run-promotion-eval-smoke.sh`
3. docs/contracts guardrails
   - `npm run -s ci:guards`

Success criteria for the supported path:

- the build proof records exact host/compiler/artifact provenance
- eval-host load either passes on a supported ABI-aligned host, or reports ABI-sensitive skip/failure explicitly
- no workflow or doc claims a true upstream compiler-target plugin path

## Phased plan

### Phase 1: qualify the supported upstream path

Keep improving the supported eval-host adapter path until:

- supported hosts/toolchains are explicit
- ABI-sensitive environments fail clearly instead of ambiguously
- recommendation docs separate upstream-host plugin support from `hxhx` native plugin support

### Phase 2: keep the true compiler-target path as research only

Do not claim support until research proves that upstream Haxe exposes:

- a real extension seam for backend/target registration or substitution
- a packaging model that does not depend on undocumented compiler patching
- a testable host/plugin ABI contract

Until then, the true compiler-target path remains a non-goal, not a hidden beta.

## Follow-up tasks

Supported eval-host adapter lane:

1. `haxe.ocaml-f1cl.8.4` (`P1`)
   - Explicit upstream Haxe host-adapter proof for reflaxe.ocaml artifacts
   - dependencies already tracked under `haxe.ocaml-f1cl.8`
2. `haxe.ocaml-rpmx.2a` (`P2`)
   - Eliminate host ABI skip in upstream Haxe eval-plugin proof lane
   - depends on the promotion-matrix proof lane, not on a new compiler-target claim

Research-only compiler-target lane:

3. `haxe.ocaml-anoy.4.1` (`P3`)
   - Probe whether upstream Haxe exposes a real compiler-target plugin seam
   - depends on this decision note staying explicit about the path being unsupported today

## Related docs

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
