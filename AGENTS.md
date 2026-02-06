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

## Local Reference Repos

- `haxe.elixir.reference`: `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference`
- Haxe compiler source (reference): `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`
- `haxe.elixir.codex` (compiler + testing patterns reference): `/Users/fullofcaffeine/workspace/code/haxe.elixir.codex`

## Licensing (MIT Goal, Keep Private for Now)

This repository is intended to become a **MIT-licensed** OCaml target *and* (eventually) a **MIT-licensed Haxe-in-Haxe compiler** (`hxhx`).

To avoid GPL “viral” obligations and preserve the ability to embed/bundle `hxhx` in proprietary apps:

- **Do not copy** upstream Haxe *compiler* source code (`vendor/haxe/src`) into this repo.
  - Reading upstream as a behavioral/architectural reference is fine; copying code is the risk.
- **Do not vendor upstream Haxe tests** into this repo.
  - Run upstream suites from a local checkout (`vendor/haxe`, ignored by git) as an oracle.
- Keep the upstream checkout **untracked** (`vendor/haxe` via `scripts/vendor/fetch-haxe-upstream.sh` or a symlink).
- Any OCaml shims (`*.ml`) must be **written from scratch** (no copy/paste from upstream compiler sources).
- Be cautious about bundling a stage0 `haxe` binary in distributions: if you ship it, you must comply with its license.
  - Prefer making `hxhx` truly non-delegating before publishing “batteries included” builds.
- Inbound contributions must be MIT-compatible; avoid accepting code with unclear provenance/licensing.

## Upstream OCaml Reference (vendored checkout)

When implementing backend semantics or Haxe-in-Haxe bootstrap behavior, cross-check against upstream Haxe’s **existing OCaml implementation**:

- Prefer working against a local `vendor/haxe` checkout (ignored by git) created via `bash scripts/vendor/fetch-haxe-upstream.sh`.
- In local dev, it’s also fine to point `vendor/haxe` at your reference checkout (e.g. symlink to `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`) for fast iteration — but keep it untracked.

When implementing semantics or compiler architecture:

- Prefer cross-checking against the upstream **OCaml** Haxe compiler code in `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe` (behavior, data structures, ordering/printing, runtime expectations).
- Prefer cross-checking our prior compiler target patterns in `/Users/fullofcaffeine/workspace/code/haxe.elixir.codex` (testing layers, acceptance workloads, CI gates).
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
- Local convenience: you may symlink `vendor/haxe` to an existing checkout (e.g. `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`) for faster iteration.

## Long-Term Acceptance Example: Haxe-in-Haxe (Production-Grade)

We want a potentially **production-ready** Haxe-in-Haxe compiler example under `examples/` over time:

- Target Haxe version: **4.3.7**
- Must eventually support **macros** (and other core compiler features), not just parsing/typechecking.
- Use the Haxe compiler source above as the primary local reference for how the real compiler is structured and how it targets OCaml.

## “Spec First” (Behavioral References)

When implementing language/runtime semantics, cross-check behavior against:

- The Haxe compiler source + tests in `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`
- The patterns and docs in `/Users/fullofcaffeine/workspace/code/haxe.elixir.codex` (testing strategy, acceptance workloads, etc.)
- `haxe.elixir.reference` for additional target/stdlib mapping ideas

Prefer adding tests that match the repo’s testing layers:

- Snapshot test (golden `.ml` output) when the key risk is codegen shape/ordering
- Portable fixture (compile → dune build → run → stdout diff) when behavior matters
- Acceptance example only when it’s a compiler-shaped workload / integration boundary

## Documentation (hxdoc)

Use hxdoc (`/** ... */`) proactively.

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
