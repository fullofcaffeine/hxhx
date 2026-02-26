# Family Portable Contract Differential Fuzzer + Minimizer (Spike v1)

This spike defines an implementation plan for seed-based, typed differential fuzzing over the portable stdlib contract.

## Scope

- Primary target for first implementation: OCaml adapter in this repository.
- Comparison targets to onboard after OCaml runner parity: Rust and Go adapters.
- Input space is constrained by the portable contract + semantic-diff corpus (`test/portable/semantic_diff/corpus_v1.json`).

## Goals

1. Detect semantic divergence between portable contract executors.
2. Produce deterministic, minimized repro fixtures for every divergence.
3. Keep CI runs reproducible and bounded.

## Non-goals

- This spike does not implement a full random language generator in CI on day one.
- This spike does not fuzz target-native APIs (`ocaml.*`, `rust.*`, `go.*`).

## Design overview

Pipeline stages:

1. **Seed selector**
   - Start from declared corpus slices.
   - Select a deterministic fixture subset per seed.
2. **Typed mutation generator**
   - Apply grammar-preserving, type-aware mutations.
   - Reject invalid mutations before execution.
3. **Oracle runner**
   - Compile/run mutated program through each adapter lane.
   - Compare normalized stdout/stderr/exit.
4. **Differential comparator**
   - Mark divergence when observable outputs differ.
5. **Failure minimizer**
   - Delta-debug AST + source-level edits while preserving divergence.
6. **Repro exporter**
   - Write minimized fixture under `test/portable/semantic_diff/generated/<id>/`.

## Generator constraints (typed + portable-safe)

Mutations must keep compilation constraints valid and remain inside portable contract modules:

- Allowed constructs:
  - expressions: literals, arithmetic, boolean ops, if/else, switch, loops, function calls
  - collections: `Array`, `Map`, `StringBuf`, `haxe.io.Bytes`
  - exceptions: `try/catch/throw` with typed catches
  - null/dynamic boundary cases already represented in seed corpus
- Disallowed constructs:
  - target-native packages (`ocaml.*`, `rust.*`, `go.*`)
  - macro/eval APIs
  - filesystem/network side effects in fuzz-generated samples
- Determinism constraints:
  - no wall-clock time
  - no random without explicit seeded source
  - no host-local absolute paths in outputs

## Oracle runner contract

Runner inputs:

- `seed`
- `targetId`
- `sliceId`
- `maxPrograms`
- `timeoutMs`

Runner outputs:

- normalized `stdout`
- normalized `stderr`
- numeric exit code
- compile/run status markers

Normalization policy:

- normalize line endings to `\n`
- strip trailing whitespace
- preserve semantic content (do not rewrite values)

Reference lanes:

- OCaml seed lane command: `npm run test:stdlib:semantic-diff:seed`
- Future adapters must implement equivalent contract markers from:
  - `docs/00-project/STDLIB_FAMILY_CONFORMANCE_RUNNER_CONTRACT_V1.md`

## Minimization approach

Minimization is two-phase:

1. **Program-level reduction**
   - Remove declarations/statements while divergence persists.
2. **Expression-level reduction**
   - Simplify expressions (replace subtrees with literals/variables) while divergence persists.

Stop conditions:

- no further reduction preserves divergence
- iteration limit reached
- time budget reached

Output requirements:

- minimized source fixture
- before/after size metrics
- deterministic replay command

## CI feasibility + reproducibility constraints

CI lanes:

- PR lane:
  - replay-only mode on committed generated repros
  - deterministic seed smoke (small `maxPrograms`)
- Nightly lane:
  - wider seed set + larger mutation budget
  - auto-artifact upload for divergence bundles

Reproducibility requirements:

- every run prints seed and config
- generator + minimizer are seed-deterministic
- timeouts are explicit and reported
- flaky outcomes are marked `unstable` and not auto-promoted

Resource caps (initial recommendations):

- PR: `maxPrograms <= 50`, per-program timeout `<= 10s`
- Nightly: `maxPrograms <= 1000`, per-program timeout `<= 15s`
- total lane timeout explicit in workflow config

## Data model (v1 draft)

Suggested report files:

- `semantic_diff_run_report.json`
- `semantic_diff_divergences.json`
- `semantic_diff_minimized_manifest.json`

Each report should include:

- `schemaVersion`
- `contractId`
- `contractVersion`
- `seed`
- run counters (`generated`, `compiled`, `diverged`, `minimized`)

## Follow-up implementation tasks (tracked)

See child tasks under `haxe.ocaml-z7f.5`:

- `haxe.ocaml-z7f.5.2` — implement typed generator skeleton + deterministic seed plumbing
- `haxe.ocaml-z7f.5.1` — implement differential runner comparator + normalized outputs
- `haxe.ocaml-z7f.5.4` — implement minimizer + repro exporter
- `haxe.ocaml-z7f.5.3` — wire PR/nightly CI lanes + artifact policy
