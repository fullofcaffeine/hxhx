# Public Scoped vs Full 1.0 Checklist

Use this page before making a public `Scoped 1.0` or `Full 1.0` claim in release notes, docs, announcements, tags, or roadmap/status updates.

Do not use an unlabeled public version claim.

The current semantic-release policy reserves versions `>=1.0.0` for Full1.
`Scoped 1.0` remains a compatibility-profile label while `haxe_ocaml-ftrhr`
owns its final public version identity. Until that xhigh decision closes, the
safe public wording is `Scoped profile candidate` under `0.x`; it is not a
separate authorization for semantic version `1.0.0`.

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
6. `FULL1_FLAKE_POLICY:PASS`
7. `FULL1_PERF_PARITY:PASS`
8. `FULL1_RELEASE_GO:PASS`
9. A prepublication `.github/workflows/gate-full1-rc.yml` run is the actual
   Full1 release source of truth and consumes authentic same-candidate child
   artifacts rather than aggregate result strings.
10. Semantic release downloads the exact RC artifact and blocks `>=1.0.0`
    unless candidate SHA/version, current manifests, artifact provenance,
    freshness, and the complete marker set validate.
11. Relevant upstream Haxe 4.3.7 suites are treated as the primary proof of equivalence; local focused regressions are only supporting evidence.

The current strict public-claim baseline is:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`
- `docs/00-project/PARITY_MAP_FULL_1_0.md`
- `docs/02-user-guide/compat/full-1.0-scope.json`
- relevant upstream Haxe 4.3.7 suite results produced by the Full1 gate stack

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

- `Scoped profile candidate`

until the exact marker set above is green and the release gate/enforcement path is in place.
