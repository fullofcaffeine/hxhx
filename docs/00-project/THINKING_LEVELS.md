# Thinking Levels

This repo uses a lightweight `thinking:*` bead-label convention so work gets the
right amount of design pressure.

## Levels

### `thinking:low`

Use for:

- mechanical doc edits
- simple renames
- obvious workflow/script wiring
- small guard checks with clear local impact

Expected approach:

- keep the change narrow
- avoid over-design
- validate with the smallest relevant check

### `thinking:medium`

Use for:

- CI workflow reshaping
- artifact handoff
- timeout/retry logic
- build/test runner scripts
- operational hardening

Expected approach:

- think in failure modes
- prefer explicit artifacts over hidden process state
- prefer short deterministic jobs over clever long-lived wrappers
- validate with local syntax/smoke checks plus a real CI run

### `thinking:high`

Use for:

- parity map / gate contract changes
- dependency graph rewiring
- macro/plugin architecture decisions
- perf-policy changes
- anything that changes what a gate is supposed to prove

Expected approach:

- make the contract explicit
- define markers and acceptance criteria first
- update docs and CI together
- record reasoning in the bead if the tradeoff is non-obvious

### `thinking:xhigh`

Use for:

- Full 1.0 scope-definition changes
- release enforcement for `>=1.0.0`
- provenance-sensitive implementation strategy
- any task where a wrong decision could create false confidence or licensing/provenance risk

Expected approach:

- require a second-pass review before closure
- preferred second-pass review: Oracle checkpoint
- acceptable fallback: explicit written design review recorded in the bead comments
- Oracle is a review tool here, not a replacement for implementation or CI evidence

## Agent Rule

When an agent claims a bead:

1. read the `thinking:*` label and match reasoning depth to it
2. if the bead has no `thinking:*` label, infer one and add it before substantial work
3. do not close a `thinking:xhigh` bead without a second-pass review note

## Current Default Heuristic

- docs wording / trivial wiring: `thinking:low`
- CI and runner mechanics: `thinking:medium`
- gate semantics / parity contracts / architecture: `thinking:high`
- release, scope, provenance: `thinking:xhigh`
