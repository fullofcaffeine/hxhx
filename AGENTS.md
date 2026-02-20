# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Beginner-Friendly Terms (Read This First)

This repo uses a few short labels a lot. Here is what they mean in plain language:

- **stage0**: your already-installed upstream `haxe` compiler binary (the "starter" compiler).
- **stage1**: the first native `hxhx` binary built using stage0.
- **stage2**: `hxhx` rebuilt by stage1. Matching stage1/stage2 behavior is a bootstrap health check.
- **stage3**: the linked/native `hxhx` pipeline path (the long-term non-delegating direction).
- **`--target ocaml`**: compatibility lane; today this may still delegate parts of work to stage0.
- **`--target ocaml-stage3`**: linked Stage3 OCaml lane inside `hxhx`; used to validate native path behavior.
- **"native reflaxe"**: running Reflaxe backend behavior through native `hxhx` paths instead of relying on stage0 delegation.

Package manager/resolver terms:

- **Lix-first policy**: prefer Lix-managed library metadata (`haxe_libraries/<lib>.hxml`) first.
- **`haxelib` support remains**: if Lix metadata is missing, fall back for compatibility.
- Current resolver order in this repo:
  1. `haxe_libraries/<lib>.hxml` (walking up directories)
  2. `lix run-haxelib path <lib>`
  3. `haxelib path <lib>`

Quick examples:

```bash
# Delegated/compatibility lane
hxhx --target ocaml -main Main -cp src

# Native linked lane
hxhx --target ocaml-stage3 -main Main -cp src --hxhx-no-emit
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## Artifact Hygiene (MANDATORY)

This repo generates large transient artifacts during bootstrap/gate workflows. Keep disk usage under control:

1. **Before heavy runs**, preview cleanup candidates (largest-first):
   ```bash
   npm run clean:dry-run -- --verbose
   ```
2. **After heavy stage0/stage3/gate runs**, clean stale temp logs:
   ```bash
   npm run clean:tmp
   ```
3. **If cleanup output needs diagnosis**, run verbose cleanup:
   ```bash
   npm run clean:tmp:verbose
   npm run clean:verbose
   ```
4. **At end of coding session** (if code changed), run:
   ```bash
   npm run clean
   ```
5. **If disk pressure remains high** (or after repeated bootstrap regen), run:
   ```bash
   npm run clean:deep
   ```

**Do not remove committed bootstrap source snapshots**:
- `packages/hxhx/bootstrap_out/*.ml` (and companion dune files)
- `packages/hxhx-macro-host/bootstrap_out/*.ml` (and companion dune files)

**Debug retention knobs**:
- default behavior is cleanup-on-finish for stage0 logs
- set `HXHX_KEEP_LOGS=1` to retain logs
- set `HXHX_LOG_DIR=/path/to/logs` to retain logs in a stable directory

Always run `git status --short` after cleanup to verify no tracked files were accidentally removed.

## Local Reference Repos

- `haxe.elixir.reference`: `<path-to-haxe.elixir.reference>`
- Haxe compiler source (reference): `<path-to-haxe.elixir.reference>/haxe`
- `haxe.elixir.codex` (compiler + testing patterns reference): `<path-to-haxe.elixir.codex>`

## Licensing (MIT Goal, Keep Private for Now)

This repository is intended to become:

- a **MIT-licensed** OCaml target for Haxe (`reflaxe.ocaml`), and
- a **MIT-licensed, production-grade Haxe-in-Haxe compiler** (`hxhx`) that can eventually act as a
  **drop-in replacement** for upstream Haxe (target version: **4.3.7**), including macros + plugin system.

To avoid copyleft obligations and preserve the ability to embed/bundle `hxhx` in proprietary apps:

- **Do not copy** upstream Haxe *compiler* source code (`vendor/haxe/src`) into this repo.
  - Reading upstream as a behavioral/architectural reference is fine; copying code is the risk.
- **Do not vendor upstream Haxe tests** into this repo.
  - Run upstream suites from a local checkout (`vendor/haxe`, ignored by git) as an oracle.
- Keep the upstream checkout **untracked** (`vendor/haxe` via `scripts/vendor/fetch-haxe-upstream.sh` or a symlink).
- Any OCaml shims (`*.ml`) must be **written from scratch** (no copy/paste from upstream compiler sources).
- Be cautious about bundling a stage0 `haxe` binary in distributions: if you ship it, you must comply with its license.
  - Prefer making `hxhx` truly non-delegating before publishing “batteries included” builds.
- Inbound contributions must be MIT-compatible; avoid accepting code with unclear provenance/licensing.

### Permissive-license success criteria (engineering target)

These are practical goals for when we can reasonably say “this is a complete, MIT-licensed compiler”
(not legal advice; engineering acceptance).

- **No upstream compiler code vendored**: `vendor/haxe` remains untracked and used only as a behavior oracle.
- **No stage0 dependency** for correctness:
  - `hxhx` can compile real projects without delegating compilation or macro execution to upstream `haxe`.
  - Stage0 may exist only as an optional dev tool (e.g. regenerating committed bootstrap snapshots).
- **Upstream behavioral gates**:
  - Gate 1: upstream unit macro suite is green via non-delegating `hxhx`.
  - Gate 2+: upstream runci workloads relevant to macros/targets become green incrementally.
- **Plugin system parity** (at least for Reflaxe targets):
  - `--library reflaxe.<target>` activates the backend (library macros + hooks) without stage0.
  - Hooks like `Context.onAfterTyping` / `Context.onGenerate` work in native mode.
- **Provenance discipline**:
  - Prefer tests + black-box oracle runs over “porting” implementation details.
  - Avoid “translate/port” wording; use “reimplement/behavior-driven”.

### Strict provenance rules (MUST follow on every change)

These are hard constraints for all contributors and all Codex changes in this repo.

**Absolute prohibitions**

- Do **not** copy, translate, or mechanically rewrite any upstream Haxe *compiler* source into this repository
  (including “retyping from memory” after reading it).
- Do **not** copy upstream Haxe tests/fixtures into this repository (even “small snippets”).
- Do **not** paste upstream Haxe compiler/test code into repo docs, bead comments, commit messages, or generated
  “repomix” snapshots that might later get committed. Keep all notes behavior-level.
- Do **not** add third-party code unless its license is MIT-compatible *and* we retain required notices.
- Do **not** commit upstream checkouts under `vendor/` (including submodules) unless explicitly approved and reviewed.

**Allowed (and expected)**

- Use upstream Haxe only as a **behavioral oracle**:
  - run upstream tests from an untracked checkout (`vendor/haxe`) and compare behavior/output,
  - use upstream CLI behavior as a reference point,
  - use upstream architecture as inspiration at the concept level.
- Write fresh implementations from:
  - behavior-level specs,
  - repo-local fixtures,
  - and black-box oracle runs.

**Clean implementation workflow**

- Before implementing a tricky behavior:
  - Add/extend a test (snapshot / portable fixture / upstream runner) that captures the behavior.
  - Write a short “behavior spec” note (what should happen, observable outputs), ideally in the relevant bead.
- If you consult upstream implementation code:
  - Only record **behavior-level** conclusions (not code structure).
  - Do not paste upstream code, and do not mirror upstream naming/structure in a way that suggests transcription.
- After changes:
  - Run `npm run ci:guards` locally (license/provenance guardrails).
  - Prefer small commits with clear intent; keep diffs reviewable for provenance.

**Documentation language**

- Prefer “reimplement” / “clean-room” / “behavior-driven” wording.
- Avoid “translate” / “port” wording when referring to upstream compiler implementation, because it tends to invite
  transcription and muddles provenance.

**Third-party notices**

- If we ever incorporate third-party code (even permissive), add/maintain `THIRD_PARTY_NOTICES.md` (or similar) with:
  - project name + license + source URL/commit,
  - what was used,
  - and any required attribution text.

### Bootstrap artifacts (generated OCaml snapshots)

To keep Stage4 macro-host selection/build **stage0-free by default**, we may commit *generated OCaml output*
from our own Haxe sources as **bootstrap snapshots**.

Current bootstrap snapshot locations:

- `packages/hxhx-macro-host/bootstrap_out/` — generated OCaml sources + dune files for `hxhx-macro-host`.
- `packages/hxhx/bootstrap_out/` — generated OCaml sources + dune files for `hxhx` (stage0-free build by default).

Rules:

- Treat these directories as **generated**: do not hand-edit files inside them.
- Regenerate only via repo scripts (behavior-preserving), and keep the diff reviewable.
- Bootstrap snapshots must be generated only from **repo-owned Haxe sources** + our backend/runtime (no upstream compiler/test sources).
- If a bootstrap snapshot must embed additional third-party code, update `THIRD_PARTY_NOTICES.md` accordingly.

**If unsure**

- If any change feels “too close” to upstream source (data structure, function layout, line-by-line mapping), stop and:
  - write a behavior-level spec first,
  - implement an alternative approach from first principles,
  - or file a bead for a clean-room/second-pass redesign.

### “Not a translation” rule (non-derivative development)

When using the upstream Haxe compiler (copyleft-licensed) as a reference, the rule is:

- Use upstream **only as an oracle for behavior** (tests, CLI output, runtime semantics).
- Reading upstream source to understand intent/constraints is OK, but **do not transcribe** upstream compiler code (OCaml → Haxe) into this repository.

Practical workflow to enforce this:

- Prefer writing or running a **test** (repo-local fixture or upstream oracle run) that demonstrates the behavior we need.
- If you must consult upstream implementation details:
  - write down a *short, behavior-level* note in the relevant bead comment (what/why/expected outcome),
  - then implement from that note + tests, not by “mechanically rewriting” the upstream code.
- Do not copy/paste code blocks, unique data structures, or large-scale organization from `vendor/haxe/src`.
  - If a solution naturally converges on a common algorithm (e.g. unification/DCE), implement it independently and document it.

Legal reality note (engineering guidance, not legal advice):

  - We cannot prevent anyone from *attempting* a claim, but we can make it easy to demonstrate good provenance:
    - upstream is not vendored,
    - changes are test-driven and documented,
    - and we are not shipping code derived from upstream compiler sources.

## Upstream OCaml Reference (vendored checkout)

When implementing backend semantics or Haxe-in-Haxe bootstrap behavior, cross-check against upstream Haxe’s **existing OCaml implementation**:

- Prefer working against a local `vendor/haxe` checkout (ignored by git) created via `bash scripts/vendor/fetch-haxe-upstream.sh`.
- In local dev, it’s also fine to point `vendor/haxe` at your reference checkout (for example, symlink to `<path-to-haxe-reference>/haxe`) for fast iteration — but keep it untracked.

When implementing semantics or compiler architecture:

- Prefer cross-checking against the upstream **OCaml** Haxe compiler code in your local Haxe reference checkout (behavior, data structures, ordering/printing, runtime expectations).
- Prefer cross-checking our prior compiler target patterns in your local `haxe.elixir.codex` checkout (testing layers, acceptance workloads, CI gates).
- If we need the upstream source inside this repo for repeatable tests, prefer a pinned fetch/submodule under `vendor/` rather than copying it (size + licensing + history).
- Optional vendored upstream checkout location (preferred for gate runners): `vendor/haxe` (create with `bash scripts/vendor/fetch-haxe-upstream.sh`)

## Upstream Haxe Source (Required Reference)

When implementing backend semantics (Haxe → OCaml) and when evolving `hxhx`, treat upstream Haxe as the source of truth:

- Use upstream tests as behavioral oracles:
  - `vendor/haxe/tests/unit`, `vendor/haxe/tests/runci`, `vendor/haxe/tests/display`
- Use upstream compiler implementation patterns as architectural references:
  - OCaml compiler sources under `vendor/haxe/src/`

Vendoring policy:

- We do **not** commit upstream Haxe into this repository.
- Instead, we keep a pinned local checkout at `vendor/haxe` (ignored by git) via:
  - `bash scripts/vendor/fetch-haxe-upstream.sh` (defaults to `HAXE_UPSTREAM_REF=4.3.7`)
  - Override path with `HAXE_UPSTREAM_DIR=/path/to/haxe` when needed.
- Local convenience: you may symlink `vendor/haxe` to an existing checkout (for example, `<path-to-haxe-reference>/haxe`) for faster iteration.

## Long-Term Acceptance Example: Haxe-in-Haxe (Production-Grade)

We want a potentially **production-ready** Haxe-in-Haxe compiler example under `examples/` over time:

- Target Haxe version: **4.3.7**
- Must eventually support **macros** (and other core compiler features), not just parsing/typechecking.
- Use the Haxe compiler source above as the primary local reference for how the real compiler is structured and how it targets OCaml.

## “Spec First” (Behavioral References)

When implementing language/runtime semantics, cross-check behavior against:

- The Haxe compiler source + tests in your local Haxe reference checkout
- The patterns and docs in your local `haxe.elixir.codex` checkout (testing strategy, acceptance workloads, etc.)
- `haxe.elixir.reference` for additional target/stdlib mapping ideas

Prefer adding tests that match the repo’s testing layers:

- Snapshot test (golden `.ml` output) when the key risk is codegen shape/ordering
- Portable fixture (compile → dune build → run → stdout diff) when behavior matters
- Acceptance example only when it’s a compiler-shaped workload / integration boundary

## Documentation (hxdoc)

Use hxdoc (`/** ... */`) proactively.

## README Maintenance

Keep `README.md` up to date as milestones land.

- When you add/change a workflow (build/test/bootstrap, stage flags, new required tools), update `README.md` in the same change.
- Prefer documenting “why/what/how” briefly and linking to the deeper doc under `docs/` when it exists.

## Bugs (Regression Tests)

When fixing a bug, add a regression test when it fits the repo’s testing layers and the behavior is stable:

- Prefer a snapshot test when the risk is codegen shape/ordering.
- Prefer a portable fixture when runtime behavior matters (compile to OCaml, build, run, stdout diff).
- Prefer an upstream oracle runner only when the behavior is best validated against upstream without vendoring.

If a regression test is not feasible (nondeterministic behavior, too expensive for CI, etc.), document why in the bead.

## Type Safety Rule (`Any`/`Dynamic`)

`Any` and `Dynamic` are forbidden by default.

- Use concrete, domain-specific types whenever possible.
- Only use `Any` or `Dynamic` at unavoidable runtime boundaries (interop/protocol/reflection/exception boundaries).
- When `Any`/`Dynamic` is truly necessary, keep it tightly scoped, convert to a typed structure immediately, and document why it is required (hxdoc or bead note).
- Do not propagate `Any`/`Dynamic` through internal compiler/core APIs.

This repo should be a **world-class, didactic example** of building a compiler backend with **Haxe + Reflaxe** that produces **idiomatic target-language code** (OCaml in this repo; the principles should also read well for targets like Rust).

- For any **vital** or **complex** class/function, write a verbose hxdoc explaining:
  - **Why** it exists (intent, constraints, alternatives considered).
  - **What** it does (inputs/outputs, invariants, edge cases, guarantees).
  - **How** it works (high-level algorithm, major steps, tradeoffs).
  - **Target mapping** (how Haxe semantics are preserved and which target idioms we emit).
  - **Examples** (short usage examples or “before/after” semantics, if helpful).
  - **Gotchas** (performance traps, correctness hazards, warning-as-error constraints, etc).
- Prefer documenting public APIs; also document internal code that is subtle, easy to misuse, or correctness-critical (codegen passes, printers, ordering/recursion logic, type mapping, runtime shims, etc.).
- If you use an **intermediate/advanced Haxe construct** that isn’t obvious, add comprehensive hxdoc on the symbol that introduces/relies on it (and link to the relevant Haxe manual section when practical). Examples include:
  - **Macros / compile-time** (`haxe.macro.*`, `@:build`, `@:autoBuild`, `macro` functions, `Context`, AST transforms).
  - **Abstracts & conversions** (`abstract`, `@:from`, `@:to`, `@:op`, `@:forward`, `@:using`).
  - **Type-system tricks** (`@:generic`, `@:multiType`, `typedef` structural types, `Dynamic`, `Null<T>`, variance/casts, `inline` behavior).
  - **Safety escape hatches** (`untyped`, `@:privateAccess`, `Reflect`, `Type`, `cast`, `Obj.magic`-style patterns).
  - **Conditional compilation** (`#if`, `-D`, feature flags) and how it affects output/backwards compatibility.

## Docs Must Stay Current (README)

When behavior, flags, workflows, or required tooling changes, update the relevant documentation in the same change:

- Keep `README.md` accurate for "getting started" and the common workflows (`npm test`, Gate runners, building/running `hxhx`).
- If the change is narrow and developer-facing, update the most relevant doc under `docs/` instead of bloating `README.md`.

## Repository Docs (README)

Keep `README.md` up to date as behavior evolves:

- When adding/changing compiler flags, bootstrap stages, CI gates, or build scripts, update `README.md` in the same PR.
- Prefer documenting:
  - the intended user workflow (install, compile, run),
  - the developer workflow (tests, gates, bootstrap regen),
  - and any environment prerequisites (Haxe 4.3.7, OCaml/dune versions, etc.).
