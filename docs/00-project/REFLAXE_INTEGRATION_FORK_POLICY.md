# Reflaxe Integration Fork Policy

## Outcome

This project maintains `fullofcaffeine/reflaxe` as its Reflaxe integration
fork. The fork can improve and extend the framework, but every change remains
reviewable, target-neutral, reproducible, and compatible with the wider
Reflaxe compiler family.

For now, framework pull requests are opened only against the fork. Do not open
or update pull requests in `SomeRanDev/reflaxe` unless the product owner changes
that policy.

`reflaxe.ocaml` and `hxhx` are important integration clients, not the semantic
owners of Reflaxe. An incident in either project may reveal a framework defect
and provide end-to-end evidence. The resulting framework API or fix must not
contain OCaml-specific types, helper names, representation choices, target
policies, or lifecycle assumptions.

## Repositories And Branch Ownership

| Role | Repository | Contract |
| --- | --- | --- |
| Upstream observation | `SomeRanDev/reflaxe` | Read and periodically synchronize; no PRs for now. |
| Maintained fork | `fullofcaffeine/reflaxe` | All framework branches, PRs, releases, and fork CI. |
| Integration consumer | `fullofcaffeine/hxhx` / this checkout | Pins an immutable reviewed fork commit and content digest. |

Never write through a shared sibling checkout. Use a clean Reflaxe worktree and
task branch, preserve the primary checkout state, push only the task branch,
and land through a fork PR.

## Upstream Synchronization

Check upstream:

- before beginning any Reflaxe fork change;
- before advancing the Reflaxe commit pinned by this repository;
- before a fork release or package evidence run;
- at least weekly while the fork is active.

Record the live upstream and fork `main` commit IDs. When they differ:

1. create a `sync/upstream-YYYYMMDD` branch from fork `main`;
2. incorporate the upstream commits without rewriting fork `main` history;
3. inventory upstream changes and identify overlaps with the fork delta;
4. resolve conflicts according to documented behavior, not merely textual
   convenience;
5. open a fork PR describing the old fork base, new upstream base, conflicts,
   resolutions, behavior risks, and exact tests;
6. run the Reflaxe suite plus risk-routed compatibility clients;
7. merge only after the fork PR has visible passing evidence.

A fast-forwardable history is helpful but not sufficient. A successful Git
merge does not prove compiler behavior or API compatibility.

## Required Pull-Request Record

Every change, including maintenance and CI changes, gets its own fork PR. The
body starts with explicit **Why**, **What**, and **How** sections, then records:

1. **Outcome:** what a Reflaxe compiler author can now rely on.
2. **Problem:** concrete old behavior and why it was wrong or limiting.
3. **Context:** the incident, request, or Bead that exposed the need.
4. **Design:** why this framework seam is the correct owner.
5. **Upstream relationship:** whether upstream lacks, differs from, or has
   since superseded the change.
6. **Family compatibility:** why the change is target-neutral and how existing
   Reflaxe compilers remain valid or migrate deliberately.
7. **Behavior changes:** generated output, lifecycle, API, diagnostics, cache,
   or performance differences that reviewers should expect.
8. **Verification:** exact Haxe versions, Reflaxe tests, compatibility clients,
   negative tests, and CI run links.
9. **Risks and rollback:** known hazards and the last known-good fork commit.
10. **Deferred scope:** what the PR intentionally does not claim.

Every behavior-changing PR also includes:

- a minimal Haxe snippet that reproduces the old behavior;
- before/after generated snippets for each target language used as compatibility
  evidence, with simplified examples labeled as such;
- the exact diagnostic and compiler phase when the old path fails before any
  target source can be emitted, instead of an invented target-language result.

The snippets are review evidence, not decoration: they should make the source
semantic contract and the practical generated-code consequence understandable
without requiring the reviewer to reconstruct either from internal Haxe AST
names.

The commit and PR body include this provenance form, specialized to the actual
incident:

```text
hxhx-agent created this because <plain-language incident and reason>.
```

Do not use a PR description that is only a filename list. The practical old
and new behavior comes first; internal names support that explanation.

## Framework Neutrality

Fork changes may introduce stronger lifecycle, identity, traversal, plugin,
diagnostic, caching, and validation facilities. They should benefit any
Reflaxe target that needs the capability.

The following are prohibited in the generic framework:

- `reflaxe.ocaml` metadata names or carrier rules;
- OCaml AST, runtime, module, representation, or ABI policy;
- `hxhx` private compiler objects or target-specific semantic decisions;
- a fallback that silently changes one target's language behavior;
- an API whose only meaningful implementation is one target's workaround.

Target-specific policy stays in its target repository. When one target is the
only initial client, the fork PR must still use a target-neutral vocabulary,
include generic framework tests, and state the reuse contract for other
targets.

## Verification Tiers

Use the narrowest tier that proves the change, then broaden according to risk:

1. **Framework unit/regression:** required for every behavior change.
2. **Reflaxe test compiler:** required for framework API and preprocessing
   changes on the declared Haxe matrix.
3. **Family compatibility client:** required when an API, typed-expression
   lifecycle, traversal, cache, or generated shape changes.
4. **`reflaxe.ocaml` canary:** required when that target exposed the incident;
   keep it focused during ordinary iteration.
5. **Heavy `hxhx` or package E2E:** reserved for pin advances, bootstrap/plugin
   integration, release candidates, and other critical lifecycle boundaries.

The heavy clients are high-value QA, not per-commit unit tests. Their cost must
not turn routine Reflaxe development into a full `hxhx` rebuild.

CI must show a scheduled run and its conclusion. No run, a skipped required
job, or an unapproved workflow is not green evidence. The fork keeps an
explicit manual-dispatch route for recovery and provenance checks.

## Pinning, Delta Inventory, And Rollback

This repository records:

- the exact fork commit;
- a path-independent SHA-256 digest of the downloaded Reflaxe source tree;
- the resolved provider and classpath;
- whether required framework capabilities are present;
- the Reflaxe identity in package/CI receipts.

Version text such as `4.0.0-beta` is descriptive, not an immutable identity.
The Git commit and content digest are the lock.

Maintain a fork-delta inventory through merged fork PRs and periodic sync PRs.
Before advancing the consumer pin, identify the last known-good pin and retain
enough evidence to restore it. Rollback changes the immutable pin and digest in
one reviewed slice; it never silently falls back to a local Haxelib cache.

## Current Baseline

On 2026-07-20, upstream and fork `main` were first synchronized at
`73a983112e039daad46b37912ab238df6bf0cf53`. The fork then merged:

- fork PR #1: lazy function field type resolution;
- fork PR #2: sound side-effect, `continue`, and semantic-envelope preservation
  in pure-expression cleanup.

The fork then merged PR #3 to preserve nested block results. Fork `main`
became `bfadffb8926e378a4ce8be4b5f66e53b2a9af216`.
The complete `reflaxe.ocaml` portable conformance corpus passed on that exact
fork commit. PRs #1 through #3 also carry the required Why/What/How record and
source-to-target examples.
GitHub reported Actions and workflows enabled but scheduled no PR or `main`
push runs. That is an open CI defect under `haxe_ocaml-7201t.3`, not passing
evidence.

This policy changes dependency governance, not product readiness. README Goals
and North Star progress remain unchanged until supported behavior and release
evidence materially improve.
