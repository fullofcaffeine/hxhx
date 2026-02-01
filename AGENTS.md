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
- Optional vendored upstream checkout location (preferred for gate runners): `vendor/haxe` (create with `bash scripts/vendor/fetch-haxe-upstream.sh`)

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
