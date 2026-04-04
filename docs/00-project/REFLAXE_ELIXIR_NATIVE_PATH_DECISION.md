# reflaxe.elixir Native Path Decision

Last reviewed: 2026-04-03

This note records the architecture decision for `haxe.ocaml-xbnp.1`:

- when `reflaxe.elixir` is pressure-tested from this monorepo,
- should we keep the external macro-host / promoted host-adapter path,
- or should we pursue a native target-core migration path inside this repo?

## Decision

Choose the external host-adapter/plugin path.

Do **not** pursue a `reflaxe.elixir` target-core migration inside this monorepo as the default or near-term path.

In practical terms:

- official native pressure-test path for `reflaxe.elixir` in this repo is the promoted host-adapter/plugin workflow
- raw source-host native verification remains diagnostic only
- a native `reflaxe.elixir` target-core migration is a non-goal for this repo unless the provenance, ownership, and acceptance constraints change materially

## Why this is the correct path

### 1. It matches the current proven native surface

The official external `reflaxe.elixir` native proof in this repo is already:

- `npm run test:hxhx:reflaxe-elixir-todo-pilot`

That lane proves:

1. fetch external `reflaxe.elixir` todo-app Haxe sources,
2. generate promoted plugin artifacts,
3. load the plugin through Stage3 backend selection,
4. compile/run a deterministic marker sample.

The testing contract already says this is the official native pressure-test surface:

- `docs/01-getting-started/TESTING.md`
- `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`

So the architecture decision should align with the lane that is already proven, documented, and intentionally scoped.

### 2. It matches the promotion matrix contract

The promotion matrix already defines the supported paths as:

1. `haxe + reflaxe.ocaml -> plugin`
2. `hxhx + reflaxe.ocaml -> built-in target`
3. `hxhx + reflaxe.ocaml -> plugin`

That matrix does **not** claim:

- a builtin `reflaxe.elixir` target inside `hxhx`
- a target-core migration requirement for external Reflaxe compilers

For `reflaxe.elixir`, the current contract is therefore:

- prove interoperability through host adapters and promoted plugin artifacts,
- not by importing or rewriting the backend into this monorepo.

### 3. It preserves the repo's licensing/provenance boundary

`reflaxe.elixir` is intentionally treated as an external fetched input in this repo.

Current repo posture already says:

- do not vendor external `reflaxe.elixir` sources here
- keep the MIT-focused monorepo boundary explicit
- use external fetched inputs for the pilot instead of subtree/submodule coupling by default

That posture fits the promoted host-adapter/plugin path well:

- the external compiler remains external
- this repo proves host/runtime interoperability
- we do not blur interoperability with ownership

A target-core migration would pressure us toward one of these less-safe shapes:

- vendoring or semi-vendoring backend logic,
- a clean-room rewrite of Elixir backend behavior inside this repo,
- or a long-lived hybrid where ownership is ambiguous.

That is a worse fit for the current repo boundary.

### 4. It avoids solving the wrong problem

The current hard problem is:

- prove that external compiler-shaped workloads can run through the native promotion lanes with explicit, reproducible evidence

The promoted plugin path already addresses that.

A target-core migration would instead create a much larger new problem:

- defining and maintaining a first-class native Elixir backend inside this monorepo

That is not required to satisfy the current promotion contract.

### 5. It matches current backend layering intent without overreaching

The backend-layering work in this repo is real:

- shared `ITargetCore`
- `ReflaxeTargetAdapter`
- builtin/provider wrapper equivalence for current native backends

But that layering is a framework for targets we own here.

It does **not** automatically imply that every external Reflaxe compiler should be migrated into this repo's target-core boundary.

For `reflaxe.elixir`, using that layering as a future option is acceptable.
Using it as the required current path is not.

## Chosen path

The chosen path is:

- external `reflaxe.elixir` sources remain outside this repo
- this repo proves native progression through promoted host-adapter/plugin artifacts
- `hxhx` is the host/runtime surface being validated
- `reflaxe.elixir` remains an external pressure-test workload, not an in-repo backend ownership target

This means the default progression model is:

1. fetch external source checkout deterministically,
2. build promoted plugin artifacts through the documented host-adapter tooling,
3. load those artifacts in `hxhx`,
4. measure acceptance through explicit proof markers and retained artifacts.

## Rejected path

Rejected as the default path:

- native `reflaxe.elixir` target-core migration inside this monorepo

That path is rejected because it would require materially broader commitments:

- backend ownership inside this repo,
- stronger provenance/legal posture around external semantics,
- new acceptance gates for a built-in or semi-built-in Elixir backend,
- and likely a much larger long-term maintenance surface.

## Concrete non-goals

These are explicitly out of scope for this decision:

1. Do not add a builtin `elixir-native` backend to `hxhx`.
2. Do not treat `reflaxe.elixir` as a target-core migration candidate that must land in `packages/hxhx-core`.
3. Do not vendor `reflaxe.elixir` sources into this repo.
4. Do not claim that raw source-host native verification is the official path.
5. Do not redefine the promotion matrix so that external compiler parity requires target-core ownership here.
6. Do not blur external workload pressure testing into semantic authority; upstream Haxe remains the semantics authority.

## Gate impact

This decision changes what counts as acceptance evidence.

### Release-relevant / official path

These are the commands that matter for the chosen path:

1. external native pilot:
   - `npm run test:hxhx:reflaxe-elixir-todo-pilot`
2. upstream-host plugin proof for the general promotion contract:
   - `bash scripts/ci/run-rpmx-haxe-plugin-proof.sh`
3. native plugin/system guardrails that keep the promotion substrate healthy:
   - `npm run test:plugins:strict-matrix`
   - `npm run -s ci:guards`

### Diagnostic only

This remains valuable, but it is not the official acceptance contract:

1. raw source-host verifier:
   - `npm run test:hxhx:reflaxe-elixir-native-verify`

That lane is useful for:

- discovering source-host gaps,
- classifying host-routing failures,
- and prioritizing future work.

It is **not** the path we should force into green before we can claim the official external native promotion path works.

## Pass/fail rule for future reconsideration

We may revisit target-core migration later, but only if all of the following become true:

1. There is a clear reason the promoted host-adapter/plugin path is structurally insufficient.
2. A clean-room ownership/provenance plan exists for any backend logic that would move here.
3. Acceptance gates are updated to prove the new path without weakening current evidence.
4. The maintenance cost of owning an Elixir backend in this repo is explicitly accepted.

If those are not true, this decision stands.

## Runnable validation commands

Official native pressure-test path:

```bash
npm run test:hxhx:reflaxe-elixir-todo-pilot
```

General promotion proof from the upstream-host side:

```bash
bash scripts/ci/run-rpmx-haxe-plugin-proof.sh
```

Promotion substrate / plugin-system health:

```bash
npm run test:plugins:strict-matrix
npm run -s ci:guards
```

Diagnostic-only raw source-host verifier:

```bash
npm run test:hxhx:reflaxe-elixir-native-verify
```

## Related docs

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
- `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
