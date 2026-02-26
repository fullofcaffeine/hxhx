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
