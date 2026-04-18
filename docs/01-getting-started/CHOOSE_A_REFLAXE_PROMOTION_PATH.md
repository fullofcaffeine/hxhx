# Choose a Reflaxe Promotion Path

Last audited: 2026-04-18

This is the operator-facing recommendation page for choosing between Reflaxe
promotion paths.

Canonical contract:

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`

Tradeoff snapshot:

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_TRADEOFFS.md`

Default recommendation: for external Reflaxe compilers, use the hxhx plugin-host
adapter path as the official external native path today.

Current evidence window: 2026-04-18, pinned Reflaxe.elixir commit
`5b322236e0627f8322394e819cf28ba6c1271a83`.

Current aggregate marker:

```text
RO_PROMOTION_MATRIX:PASS
```

## Quick Decision Table

| If you need | Choose | Why |
| --- | --- | --- |
| Upstream-compatible baseline behavior | `haxe + reflaxe.ocaml -> plugin` | It keeps upstream Haxe semantics and is the easiest comparison oracle. |
| External Reflaxe compiler promotion through hxhx native infrastructure | `hxhx + reflaxe.ocaml -> plugin` | It is the current official external native path, has a pinned Reflaxe.elixir pilot, and keeps rollout decoupled from hxhx releases. |
| Backend logic shipped inside hxhx | hxhx built-in backend | Use only when the backend is owned by the hxhx distribution and the tighter release coupling is acceptable. |

## Path A: Upstream Haxe Plugin

Use this when:

- you want the lowest-risk compatibility baseline,
- you need behavior close to upstream Haxe 4.3.7,
- or you are diagnosing whether a failure is specific to hxhx native lanes.

Validation:

```bash
npm run test:rpmx:haxe-plugin
```

Expected success marker:

```text
RPMX_HAXE_PLUGIN:PASS
```

Current timed artifact:

```text
.artifacts/rpmx/haxe-plugin/20260418-060631/rpmx-haxe-plugin.summary.json
```

Measured proof total: 3.969s.

Main cost: this is not non-delegating hxhx native evidence.

## Path B: hxhx Plugin Host Adapter

Use this when:

- you want the official external native path for Reflaxe.elixir-style compiler
  workloads,
- you can manage plugin manifests and OCaml ABI compatibility,
- and you need native hxhx substrate evidence without pretending the backend is
  built into the hxhx binary.

Validation:

```bash
npm run test:rpmx:hxhx-plugin
```

Expected success marker:

```text
RPMX_HXHX_PLUGIN:PASS
```

Current timed artifact:

```text
.artifacts/rpmx/hxhx-plugin/20260418-060711/rpmx-hxhx-plugin.summary.json
```

Measured proof total: 3.911s with a reused hxhx bytecode binary. The pilot
breakdown records 0.265s plugin promotion, 2.281s hxhx compile, and 0.044s
generated Node execution.

Main cost: plugin artifacts and host ABI must be deployed together.

## Path C: hxhx Built-in Backend

Use this when:

- the backend is part of the hxhx distribution,
- you control release packaging,
- and you want no runtime plugin artifact.

Use this as a compile/native-build proof lane for external Reflaxe compiler
promotion when you need to prove the hxhx built-in `reflaxe.ocaml` path can
build the compiler entrypoint without a runtime plugin artifact:

```bash
npm run test:rpmx:hxhx-builtin
```

Current success marker:

```text
RPMX_HXHX_BUILTIN:PASS
```

Current timed artifact:

```text
.artifacts/rpmx/hxhx-builtin/20260418-120644/rpmx-hxhx-builtin.summary.json
```

Measured proof total: 17.365s with a reused hxhx bytecode binary. The hxhx
Stage3 compile/native-build phase accounts for 17.137s.

This proof builds the pinned Reflaxe.elixir `Run` compiler entrypoint through
non-delegating hxhx `--ocaml` and records the resulting native executable in
`.artifacts/rpmx/hxhx-builtin/<run-id>/`. It is compile/native-build evidence,
not a replacement for end-to-end external target runtime validation.

## Raw Source-Host Reflaxe HXML

Raw source-host invocations such as external `compile.hxml` or `build-tests.hxml`
under `hxhx` remain diagnostic baseline evidence under the current contract.
They are not the official external native path unless the repo deliberately
widenes native scope to generic Reflaxe custom-target discovery.

## Migration Guidance

Start with upstream Haxe plugin mode if you are proving compatibility or
isolating a target-level issue.

Move to hxhx plugin-hosted promotion when you need native hxhx infrastructure
with external compiler workloads.

Move to hxhx built-in when you need no plugin artifact and you can accept the
tighter release/distribution coupling. Keep hxhx plugin-hosted promotion as the
default external Reflaxe path when operational decoupling matters more.
