# Glossary (Beginner-Friendly)

This page defines project terms in plain language.

## Core projects

- `hxhx`: the compiler product in this repo.
- `reflaxe.ocaml`: the OCaml backend/runtime package used by workflows in this repo and also usable with upstream `haxe`.
- upstream `haxe`: the existing compiler used as behavior oracle and bootstrap tool (`stage0`), not as implementation source.

## Execution modes (user-facing)

- **Delegated mode**: `hxhx` forwards compile work to upstream `haxe` for compatibility lanes.
- **Native mode**: `hxhx` runs its own compile pipeline and native backends; stage0 can be explicitly forbidden.

Use these terms first. They are what users care about.

## Backend terms

- **Builtin backend**: backend compiled into `hxhx` and shipped with the binary.
- **Backend plugin**: backend loaded at runtime from a native OCaml dynlink artifact (`.cmxs` / `.cma`) via manifest.
- **Native promotion**: turning a Reflaxe-based compiler/target into a native plugin artifact.

## Profile terms (OCaml output)

- **portable**: compatibility-first output; default profile.
- **metal**: strict, native-leaning profile; faster when code is metal-safe, with stricter constraints.

## CI gates (plain English)

- **Gate 0**: local core checks (repo invariants, smoke coverage).
- **Gate 1**: upstream macro/unit compatibility baseline.
- **Gate 2**: wider upstream macro/runci workload checks.
- **Gate 3**: target/workflow compatibility checks (scoped matrix).
- **Gate 4**: distribution and performance/acceptance checks.

## Internal stage terms (contributors)

These are contributor architecture terms, not primary onboarding language:

- `stage0`: upstream `haxe` bootstrap/oracle compiler.
- `stage1`: first `hxhx` binary produced from stage0.
- `stage2`: `hxhx` rebuilt by stage1 (bootstrap health check).
- `stage3`: native `hxhx` typing/backend driver lane.
- `stage4`: macro host protocol/plugin ABI lane.

If you are new, prefer **delegated** vs **native** terminology and use stage terms only when reading architecture docs.
