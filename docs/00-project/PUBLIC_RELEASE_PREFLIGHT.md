# Public Release Preflight

Use this checklist before a public release or major public PR.

For whether you may say `Scoped 1.0` or `Full 1.0` publicly at all, use:

- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

## 1) Secret scan (full history)

```bash
npm run guard:gitleaks
```

## 2) Repository guardrails + provenance enforcement

```bash
npm run ci:guards
```

This includes:

- version/license/provenance checks
- bootstrap snapshot backend-kind parity (`linked-provider` / `ocaml-dynlink`) between source and `packages/hxhx/bootstrap_out`
- upstream fixture-literal provenance boundary enforcement
- legacy path checks
- machine-local absolute path leak checks
- backend/provider boundary checks
- deterministic Haxe formatting checks

For direct release assertions, run:

```bash
npm run guard:bootstrap-plugin-kinds
npm run guard:no-upstream-fixture-literals
```

For any `Scoped 1.0` release candidate/tag, both guards above must be green.
For any `Full 1.0` or `>=1.0.0` candidate, also use:

- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`
- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`

For every published version, the release workflow must verify the exact Core QA
route artifact for the candidate commit. That proof covers the complete change
range since the preceding release tag, so a small documentation or expected-
output follow-up cannot make an earlier compiler/runtime change look cheap. The
focused local contract is:

```bash
npm run test:release:core-qa-proof
```

Manual publication additionally requires the successful Core workflow run ID
and attempt. A provenance-only dry run does not publish and may omit them.

This rule fixes a concrete release-process defect. `v0.23.1` was published
after its final report-only commit passed the inexpensive Q1 checks, while
earlier unreleased runtime and macro-host changes in the same candidate had not
yet completed their required Q3 run. The published tag remains part of the
project history; the cumulative proof prevents a later inexpensive commit from
hiding unfinished validation in future releases.

The semantic-release publication path blocks candidate versions `>=1.0.0`
through `scripts/release/full1-release-enforcement.js` unless
`FULL1_RELEASE_GO_MARKER=FULL1_RELEASE_GO:PASS` and
`FULL1_RC_SUMMARY_JSON=<path-to-full1-rc.summary.json>` are supplied.

## 3) Strict replacement-readiness markers (M7)

```bash
npm run test:upstream:replacement-ready:strict
```

Expected strict markers in output:

- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

Macro runtime mode expectation for native lanes:

- default should emit `hxhx_macro_runtime_mode=inproc`.
- emergency rollback is allowed via:
  - `HXHX_MACRO_RUNTIME_MODE=external-host`
  - or `--hxhx-macro-runtime external-host`

## 4) Build dist with stage0 forbidden

```bash
HXHX_DIST_FORBID_STAGE0=1 bash scripts/hxhx/build-dist.sh
```

## 5) Dist copyleft contamination assertion (no copyleft payloads)

```bash
npm run guard:dist-copyleft
```

This guard scans `dist/hxhx` and fails if:

- copyleft license markers appear in bundled text payloads, or
- a disallowed bundled path (for example `lib/reflaxe.elixir`) is present.

## 6) Combined preflight shortcuts

```bash
npm run release:preflight
npm run release:preflight:full
```

- `release:preflight`: repo-only safety checks (`gitleaks` + `ci:guards`)
- `release:preflight:full`: strict M7 + stage0-forbidden dist build + dist copyleft scan

## 7) Final verification before push

```bash
git status --short
```

Expected: no unexpected tracked file changes.
