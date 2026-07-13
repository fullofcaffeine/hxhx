# Full1 Release Go/No-Go

Last audited: 2026-07-13

This page explains what must happen before the project can publish a public
`Full 1.0` release. It does not say that Full1 is ready today.

The simpler `Scoped profile` is a different claim. It stays under `0.x` unless
the separate version-identity decision changes that policy.

## The idea in plain language

Think of a release-candidate (RC) result as a receipt for one exact build.
The receipt is useful only when it answers all of these questions:

- Which candidate SHA and version did we test?
- Which workflow run and run attempt produced each result?
- Which exact artifact supplied each pass marker?
- Does each downloaded artifact still match its recorded artifact digest?
- Are the results recent enough, complete, and based on the current manifests?

The release job must download that exact receipt and check out that exact
candidate before it may publish. A receipt for another commit, an older retry,
or a hand-written marker is rejected.

## Sources of truth

- Scope manifest: `docs/02-user-guide/compat/full-1.0-scope.json`
- Public claim checklist: `docs/00-project/PUBLIC_1_0_CHECKLIST.md`
- Prepublication RC workflow: `.github/workflows/gate-full1-rc.yml`
- Child-artifact collector: `scripts/ci/full1-rc-artifact-collector.js`
- RC evaluator: `scripts/ci/full1-rc-gate.js`
- Release artifact downloader: `scripts/release/download-full1-rc-artifact.js`
- Release-side enforcement: `scripts/release/full1-release-enforcement.js`
- RC decision file: `.artifacts/full1/rc/full1-rc.summary.json`

The scope manifest owns the required marker list. The parity map owns the
declared Gate3 target list. The evaluator reads both files from the candidate
commit; it does not accept marker strings from command-line arguments.

## Prepublication flow

1. A maintainer chooses an exact candidate version and commit, then manually
   starts `.github/workflows/gate-full1-rc.yml` before publication.
2. The RC workflow runs the strict suite/target, macro/eval, plugin, performance,
   and policy lanes on that same commit.
3. Every child uploads an artifact whose name includes both the workflow run ID
   and run attempt.
4. `scripts/ci/full1-rc-artifact-collector.js` downloads those exact artifacts.
   It checks their GitHub identity and ZIP digest, then validates the result
   inside each artifact. A workflow result string alone is not evidence.
5. `scripts/ci/full1-rc-gate.js` writes `full1-rc-summary.v2`. Aggregate markers
   such as suite-matrix and macro/eval parity are derived from accepted child
   evidence; callers cannot type them in.
6. `.github/workflows/release.yml` is given the exact RC run ID and attempt. It
   downloads `full1-rc-summary-<run-id>-<attempt>`, verifies it, checks out the
   candidate SHA from the summary, and runs release-side enforcement.
7. Semantic release may publish only when every check still passes.

A later post-publication check may compare the tag and published artifacts with
the RC receipt, but it is audit-only. It cannot authorize a release that has
already happened.

## What `full1-rc-summary.v2` records

The summary binds:

- candidate SHA and candidate version;
- scope-manifest and parity-map digests;
- RC workflow run ID, run attempt, and timestamps;
- each child workflow file, artifact ID, artifact name, artifact digest, and
  summary digest;
- the evidence tier and freshness result for every child;
- `requiredMarkers`, `presentMarkers`, and `missingMarkers`;
- the child source or sources behind every accepted marker;
- a final `go` or `no-go` decision.

Synthetic contract fixtures are useful for testing the evaluator, but they are
marked synthetic and can never become release evidence.

## Go decision

A public `Full 1.0` claim is allowed only when all of these are true:

1. The prepublication RC workflow completed successfully for one exact
   candidate SHA and version.
2. Every required child artifact came from the same run and run attempt.
3. Every child artifact is authentic, unexpired, recent enough, and valid for
   its declared evidence role.
4. `requiredMarkers` exactly matches the current scope manifest, excluding the
   final release marker.
5. `missingMarkers`, `missingArtifacts`, and `invalidArtifacts` are empty.
6. The evaluator recorded `decision=go` and `FULL1_RELEASE_GO:PASS`.
7. The release workflow downloaded and verified that exact RC artifact, then
   checked out the same candidate SHA.
8. Release-side enforcement recomputed the marker result from the child records
   and still passed.
9. Public wording explicitly says `Full 1.0` and passes
   `docs/00-project/PUBLIC_1_0_CHECKLIST.md`.

## No-go decision

Treat the candidate as a no-go when any required item is missing or cannot be
trusted. Examples include:

- `FULL1_RELEASE_GO:PASS` is absent;
- a required suite, target, macro, eval, plugin, or performance marker is
  missing;
- an artifact is missing, stale, expired, malformed, synthetic, or has a digest
  mismatch;
- the candidate SHA, version, manifest digest, run ID, or run attempt differs;
- a required workflow was skipped, cancelled, or inferred green from a job
  status without a valid artifact;
- a quarantine or retry violates the Full1 flake policy;
- the public wording makes an ambiguous `1.0` claim.

A no-go summary is still uploaded. That is useful diagnostic evidence, but it
cannot authorize publication.

## Safe handoff dry run

The RC workflow has a `provenance_only` mode. It runs the policy evidence and
artifact handoff without paying for the full compiler matrix. Because the real
semantic artifacts are deliberately absent, the RC result must be no-go.

The release workflow has a matching `provenance_dry_run` mode. It downloads the
no-go artifact, checks out its candidate, proves that release enforcement
rejects it, prints `FULL1_RELEASE_HANDOFF_DRY_RUN:NO_GO_EXPECTED`, and never runs
semantic release. This proves the plumbing without pretending the compiler is
Full1-ready.

## Relationship to semantic release

`scripts/release/full1-release-enforcement.js` is wired as semantic-release's
`verifyReleaseCmd` in `package.json`. Versions below `1.0.0` keep their existing
path. Any candidate version `>=1.0.0` requires the verified v2 receipt and exact
artifact identity supplied by `.github/workflows/release.yml`.

This is release-safety machinery, not compatibility evidence by itself. Full1
remains no-go until the real required lanes produce authentic, same-candidate
green artifacts.
