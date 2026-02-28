# Reflaxe.Elixir Todo-App Promotion Pilot

This guide is a reproducible pilot for compiling code from the external `reflaxe.elixir` todo-app example through the `hxhx` native promotion lane.

## Goal

Prove an end-to-end path:

1. fetch external todo-app Haxe sources,
2. generate native backend plugin artifacts (`plugin-init` + `promote-backend-plugin` path),
3. load that plugin through Stage3 backend selection,
4. compile and run a deterministic sample.

## One-command run (clean checkout)

```bash
npm run test:hxhx:reflaxe-elixir-todo-pilot
```

Optional pinned reference:

```bash
REFLAXE_ELIXIR_REF=<tag-or-commit> npm run test:hxhx:reflaxe-elixir-todo-pilot
```

Expected terminal markers:

- backend selection marker:
  - `backend_selected_impl=provider/js-native-wrapper`
- then either:
  - success markers:
    - `TODO_PILOT:sum=6`
    - `pilot_sample_hash=<hash>`
    - `PILOT_REFLAXE_ELIXIR_TODO:PASS`
  - or known-blocker marker:
    - `PILOT_REFLAXE_ELIXIR_TODO:BLOCKED`

## What the pilot proves

- External `reflaxe.elixir` todo-app sources are consumable in a native plugin lane.
- Pilot verifies a stable todo-app sample module hash (`server/services/MockOAuthIdentity.hx`) from the fetched checkout.
- Promotion scaffolding/build/load are stable with a deterministic output check.
- Stage3 backend selection can be driven by promoted plugin manifest input.

## Known blocker behavior

If Stage3 emits:

- `[js-native:unsupported_expr] kind=EUnsupported detail=function`

the script reports:

- `pilot_blocker=...`
- `PILOT_REFLAXE_ELIXIR_TODO:BLOCKED`

and exits successfully by default (manual/report lane behavior).

To enforce hard failure instead:

```bash
HXHX_PILOT_STRICT=1 npm run test:hxhx:reflaxe-elixir-todo-pilot
```

## What the pilot does not prove

- It does not claim full native `elixir` backend support inside `hxhx` yet.
- It does not replace upstream `haxe` + `reflaxe.elixir` workflows.
- It does not vendor external sources into this repo.

## External source integration decision

We evaluated three options for referencing `reflaxe.elixir/examples/todo-app/src_haxe`:

| Option | Pros | Cons | Decision |
| --- | --- | --- | --- |
| Git submodule | Pinned ref, discoverable in tree | Extra clone/init steps; easy to drift in contributor workflows; keeps external history wiring in main repo | Not selected |
| Git subtree | Single-repo checkout UX | Copies external code into this repo; high update friction; poor provenance boundary for this monorepo | Not selected |
| Scripted fetch (pinned ref support) | Clean provenance boundary, no vendored code, easy ref pinning in CI/manual runs | Requires network access and fetch time | **Selected default** |

Selected default implementation:

- `scripts/vendor/fetch-reflaxe-elixir-upstream.sh`
- `scripts/hxhx/run-reflaxe-elixir-todo-promotion-pilot.sh`

The fetched checkout is kept under `vendor/reflaxe-elixir` (git-ignored by default) unless `REFLAXE_ELIXIR_DIR` is provided.

## CI mode

This pilot is intentionally **non-required** for PR merges.

- Local/manual lane: `npm run test:hxhx:reflaxe-elixir-todo-pilot`
- GitHub manual lane: `.github/workflows/reflaxe-elixir-pilot.yml`

This keeps core CI fast while preserving a repeatable promotion pilot lane for maintainers.

## License/provenance boundary

The external `reflaxe.elixir` repository remains outside this monorepo’s tracked source tree.
Do not vendor/copy external repository sources into this repository as part of this pilot.
