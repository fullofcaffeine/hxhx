# Glossary (Beginner-Friendly)

This page defines project terms in plain language.

Canonical beginner references:

- Lanes + profiles + gate purpose table: `docs/02-user-guide/concepts/execution_modes.md`
- Exact preset delegation matrix: `docs/02-user-guide/concepts/what_delegates_today.md`
- Workflow/gate mapping: `docs/00-project/CI_GATES.md`

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
- **Haxe-provider (legacy term)**: old wording for what is now the `linked-provider` manifest kind.
- **Native promotion**: turning a Reflaxe-based compiler/target into a native plugin artifact.

## Profile terms (OCaml output)

- **portable**: compatibility-first output; default profile.
- **metal**: strict, native-leaning profile; faster when code is metal-safe, with stricter constraints.

## Planned M22 SDK terms

These are planning terms, not current supported functionality. They do not
rename the existing OCaml output profiles above.

- **Backend host service**: a typed, versioned, capability-limited action that
  the compiler host provides to backend/target code after the backend-facing
  program is frozen.
- **Evaluated host-neutral preset**: the planned upstream Haxe/Reflaxe
  development form. Early M22 feedback called this the portable profile; the
  qualified name avoids collision with `ocaml_profile=portable`.
- **Native host-neutral preset**: the same target core compiled through
  `reflaxe.ocaml`, while privileged `hxhx` services remain masked. Early M22
  feedback called this native-portable or accelerated.
- **`hxhx`-integrated preset**: native plugin or builtin execution with
  declared `hxhx` facts/services negotiated before target execution. Early M22
  feedback called this native-integrated.
- **Required semantic service**: a fact/action whose absence or incompatible
  version would risk wrong output, so compilation fails before target emission.
- **Optional optimization service**: a service that may be absent only when a
  proven semantics-preserving fallback exists.
- **Phase provider**: a callback capable of changing an earlier compiler phase
  or the program before the backend boundary. It is not an M22 v1 backend
  service; Stage4 or the customization/variation architecture owns its design.
- **Unsafe internal adapter**: an exact-host research bridge that exposes raw or
  unversioned compiler internals. It cannot satisfy an M22 support claim.

## CI gates (plain English)

- **Gate 0**: local core checks (repo invariants, smoke coverage).
- **Gate 1**: upstream macro/unit compatibility baseline.
- **Gate 2**: wider upstream macro/runci workload checks.
- **Gate 3**: target/workflow compatibility checks (scoped matrix).
- **Gate 4**: distribution and performance/acceptance checks.

## Milestone tags (`Mxx`)

- `Mxx` labels are internal engineering milestone tags used in tests, docs, and bead planning.
- **M13**: OCaml tooling/output polish lanes (dune layouts, `.mli`, source maps).
- **M14**: native backend/plugin/platform integration lanes.

These tags are contributor shorthand. New users can ignore them and follow `docs/01-getting-started/START_HERE.md`.

## Internal stage terms (contributors)

These are contributor architecture terms, not primary onboarding language:

- `stage0`: upstream `haxe` bootstrap/oracle compiler.
- `stage1`: first `hxhx` binary produced from stage0.
- `stage2`: `hxhx` rebuilt by stage1 (bootstrap health check).
- `stage3`: native `hxhx` typing/backend driver lane.
- `stage4`: macro host protocol/plugin ABI lane.

If you are new, prefer **delegated** vs **native** terminology and use stage terms only when reading architecture docs.
