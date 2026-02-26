# Portable Semantic-Diff Corpus (Seed v1)

This directory holds the shared, repo-authored semantic-diff corpus used to compare portable behavior across family targets (OCaml/Go/Rust).

## Scope

- Fixtures are **repo-authored only**.
- Upstream Haxe remains an oracle for behavior, not a fixture source.
- Corpus slices select fixture IDs from `test/portable/fixtures`.

## Current artifacts

- `corpus_v1.json` — seed corpus manifest + first slice (`core_seed_v1`)
- `CONTRIBUTING.md` — rules for adding/updating semantic-diff fixtures

## Seed slice command (OCaml adapter)

```bash
npm run test:stdlib:semantic-diff:seed
```

This resolves `core_seed_v1` from `corpus_v1.json` and runs those fixtures through the portable runner lane.

## Typed generator skeleton (deterministic)

Run deterministic typed mutation-plan generation + replay verification:

```bash
npm run test:stdlib:semantic-diff:generator
```

Direct generator usage:

```bash
node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js \
  --seed 1337 \
  --count 24 \
  --slice core_seed_v1 \
  --out test/portable/semantic_diff/generated/typed_seed_plan_core_seed_v1_1337.json \
  --no-print-json
```

Replay from saved plan:

```bash
node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js \
  --replay-config test/portable/semantic_diff/generated/typed_seed_plan_core_seed_v1_1337.json \
  --no-print-json
```

## Comparator smoke (normalized observable outputs)

Run adapter reports + comparator end-to-end:

```bash
npm run test:stdlib:semantic-diff:comparator
```

This command:

1. runs the OCaml adapter observable runner twice,
2. compares normalized `stdout`/`stderr`/exit outputs,
3. emits a deterministic divergence report, and
4. fails if `divergenceCount != 0`.
