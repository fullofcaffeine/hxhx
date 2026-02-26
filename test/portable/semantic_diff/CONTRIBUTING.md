# Semantic-Diff Corpus Contribution Rules

These rules keep the corpus deterministic and clean-room.

## Fixture rules

1. Add fixtures under `test/portable/fixtures/<fixture_id>/` using the existing portable fixture shape (`build.hxml`, `src/**`, `expected.stdout`, optional `expected.stderr`).
2. Keep fixture scope narrow (single semantic edge per fixture when possible).
3. Fixture IDs must be stable and descriptive (`snake_case`).

## Provenance rules

1. Do not copy upstream Haxe tests or source snippets.
2. Use upstream only as behavioral oracle when validating expected behavior.
3. Record behavior-level notes in beads/PR text when expected output is non-obvious.

## Slice rules

1. Register slices only in `corpus_v1.json`.
2. Slice fixture order must be deterministic and intentional.
3. New slices must declare focus areas and rationale.

## Quality rules

1. New/changed fixtures must pass:
   - `npm run test:stdlib:semantic-diff:seed` (if seed slice touched)
   - relevant portable/stdlib lanes (`npm run test:portable`, `npm run test:stdlib:portable:tier1` as applicable)
2. Keep outputs deterministic (avoid host-local paths, wall-clock time, random values).
