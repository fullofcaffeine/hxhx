# Full1 Release Go/No-Go

Last audited: 2026-07-12

This page defines the release decision boundary for a public `Full 1.0`
claim only. It does not redefine `Scoped 1.0`, and it must not be used to
block or silently rename the separate scoped claim path.

## Sources of truth

- Scope manifest: `docs/02-user-guide/compat/full-1.0-scope.json`
- Public claim checklist: `docs/00-project/PUBLIC_1_0_CHECKLIST.md`
- RC workflow: `.github/workflows/gate-full1-rc.yml`
- RC evaluator: `scripts/ci/full1-rc-gate.js`
- RC summary artifact: `.artifacts/full1/rc/full1-rc.summary.json`

The scope manifest owns the required `Full 1.0` marker set. The RC evaluator
must read that manifest and emit `FULL1_RELEASE_GO:PASS` only when every
required marker except the release marker itself is present.

## Current implementation status

The current `>=1.0.0` enforcement is fail-safe when RC inputs are absent, but
the positive publication path does not yet implement this complete contract.
The RC workflow currently runs automatically only after publication, derives
detailed markers from aggregate job status instead of verified child artifacts,
and emits a v1 summary without candidate/artifact provenance. The semantic
release workflow does not download an RC artifact.

Therefore no current workflow run can authorize a public Full1 publication.
`haxe_ocaml-7c1ke` owns the prepublication, same-candidate artifact and release
handoff correction. Contract/evaluator fixtures prove only their policy logic.

## Go decision

A public `Full 1.0` claim is allowed only when all of these are true:

1. `.github/workflows/gate-full1-rc.yml` completed successfully for the release
   candidate commit.
2. The RC evaluator printed `FULL1_RELEASE_GO:PASS`.
3. The uploaded RC summary uses the candidate-bound schema accepted by release
   enforcement; the current v1 schema is not sufficient for positive release
   authorization.
4. `missingMarkers` in that summary is empty.
5. `requiredMarkers` in that summary matches the current `Full 1.0` marker set
   from `docs/02-user-guide/compat/full-1.0-scope.json`, excluding
   `FULL1_RELEASE_GO:PASS`.
6. The public release wording says `Full 1.0` explicitly and passes
   `docs/00-project/PUBLIC_1_0_CHECKLIST.md`.
7. The summary binds candidate SHA/version, current manifest digests, source
   workflow runs/attempts, child artifact identities/digests, timestamps,
   evidence tiers, and freshness decisions.
8. Semantic release downloads and validates exactly that prepublication RC
   artifact before publishing.

## No-go decision

Treat the release candidate as a no-go for `Full 1.0` if any of these are true:

- `FULL1_RELEASE_GO:PASS` is absent.
- Any required marker is missing from the RC summary JSON.
- The RC summary artifact is missing, stale, malformed, or from a different
  commit.
- The flake policy has an expired quarantine entry or an unapproved retry.
- A workflow was skipped, cancelled, or inferred green without producing the
  expected marker.
- Release wording uses ambiguous `1.0` language instead of saying `Scoped 1.0`
  or `Full 1.0`.

## Relationship to release enforcement

This page defines the go/no-go decision model. The semantic-release publication
path enforces it through `scripts/release/full1-release-enforcement.js`, wired
as `verifyReleaseCmd` in `package.json`.

For any candidate version `>=1.0.0`, publication requires:

- `FULL1_RELEASE_GO_MARKER=FULL1_RELEASE_GO:PASS`
- `FULL1_RC_SUMMARY_JSON=<path-to-full1-rc.summary.json>`

The current script recognizes `full1-rc-summary.v1`, reports
`FULL1_RELEASE_GO:PASS`, and requires an empty `missingMarkers` list. This is a
negative safety boundary only until `haxe_ocaml-7c1ke` lands and the release
path also validates candidate identity, current manifests, authentic child
artifacts, digests, attempts, timestamps, and freshness.
