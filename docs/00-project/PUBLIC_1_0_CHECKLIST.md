# Public Scoped vs Full 1.0 Checklist

Use this page before making a public `Scoped 1.0` or `Full 1.0` claim in release notes, docs, announcements, tags, or roadmap/status updates.

Do not use an unlabeled public version claim.

Public wording must be explicit as either:

- `Scoped 1.0`
- `Full 1.0`

That rule exists so the project does not blur a practical replacement-ready claim into a strict Haxe-4.3.7-equivalence claim.

## Scoped 1.0

You may say `Scoped 1.0` publicly only when all of the following are true:

1. `M7_STRICT_STAGE0:PASS`
2. `M7_REPLACEMENT_READY:PASS`
3. The documented native/delegated lane contract matches the actual CLI:
   - `--ocaml`
   - `--js <file>`
   - `--ocaml-eval`
   - `--compat`
4. No known scoped release blockers remain open for the declared ship surface.
5. The release/readme/docs story is still aligned with the current scoped contract.

The current scoped public-claim baseline is:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- `docs/01-getting-started/HXHX_1_0_ROADMAP.md`

## Full 1.0

You may say `Full 1.0` publicly only when all of the following are true:

1. `FULL1_SUITE_MATRIX:PASS`
2. `FULL1_MACRO_PARITY:PASS`
3. `FULL1_EVAL_NATIVE:PASS`
4. `FULL1_MACRO_EVAL_PARITY:PASS`
5. `FULL1_PLUGIN_PARITY:PASS`
6. `FULL1_PERF_PARITY:PASS`
7. `FULL1_RELEASE_GO:PASS`
8. The Full1 RC workflow is the actual release source of truth.
9. The release workflow blocks `>=1.0.0` claims without that RC result.

The current strict public-claim baseline is:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/PARITY_MAP_FULL_1_0.md`
- `docs/02-user-guide/compat/full-1.0-scope.json`

## Public wording rule

Before any public claim:

1. Choose the claim level explicitly:
   - `Scoped 1.0`
   - `Full 1.0`
2. Verify the marker set for that claim.
3. Verify the corresponding release policy and gate docs still match the implementation.

Do not use:

- `1.0` by itself
- `production ready` by itself
- `Haxe 4.3.7 equivalent` unless the Full 1.0 checklist is actually green

## Practical release shorthand

If the goal is a practical public claim today, the safer wording is:

- `Scoped 1.0 candidate`

until the exact marker set above is green and the release gate/enforcement path is in place.
