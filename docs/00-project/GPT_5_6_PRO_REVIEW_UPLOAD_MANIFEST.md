# GPT-5.6 Pro Whole-Repo Review Upload Manifest

Prepared: 2026-07-12

Engineering baseline: `fullofcaffeine/hxhx` commit `2ca1eaae`

Companion prompt: `GPT_5_6_PRO_WHOLE_REPO_REVIEW_PROMPT.md`

This manifest keeps the external review broad enough to test the real plan
while avoiding generated/dependency noise and provenance mistakes.

## Recommended upload order

### 1. Required: the review prompt

Upload this file first:

- `docs/00-project/GPT_5_6_PRO_WHOLE_REPO_REVIEW_PROMPT.md`

Tell GPT-5.6 Pro that this is the controlling task and output contract.

### 2. Required: `fullofcaffeine/hxhx`

Repository:

- `https://github.com/fullofcaffeine/hxhx`
- engineering baseline: `2ca1eaae`
- upload the later prompt-package commit if convenient; treat `2ca1eaae` as the
  reviewed engineering baseline because the later delta only adds the review
  package and bead bookkeeping.

Preferred form when the client accepts the full tracked repository:

```bash
git archive --format=zip --output ../hxhx-gpt56-whole-repo.zip HEAD
```

`git archive` is preferred over zipping the working directory because it omits
`.git`, ignored vendor checkouts, dependencies, local artifacts, and secrets by
construction. The tracked repository is roughly 60 MB across about 3,247 files.

The full archive includes committed generated bootstrap snapshots and test
snapshots. They are useful for regeneration/footprint review, but the prompt
instructs the reviewer not to mistake them for hand-written architecture.

### 3. Recommended: upstream Haxe 4.3.7

Repository/tag:

- `https://github.com/HaxeFoundation/haxe`
- exact tag: `4.3.7`

Purpose:

- behavior and public architecture reference;
- upstream suite/target inventory;
- compiler target/module ownership comparison;
- stdlib provenance boundary.

This is not an implementation donor. The review prompt prohibits copying,
translation, mechanical rewriting, or vendoring upstream compiler source and
tests into `hxhx`.

If context is tight, provide only:

- top-level build/package metadata;
- target/compiler module layout under `src/**`;
- suite/runner inventory under `tests/**` without generated outputs;
- `std/**` only when reviewing the stdlib contract.

Do not include the dirty ignored `vendor/haxe` working directory from the main
repo. Use a clean archive of tag `4.3.7`.

### 4. Recommended: Reflaxe framework 4.0.0-beta

Repository:

- `https://github.com/SomeRanDev/reflaxe`
- version used by the main repo: `4.0.0-beta`
- exact source revision recorded by the resolved Lix package:
  `430b4187a6bf4813cf618fc3a73ccf494a2ab9f5`

Purpose:

- validate assumptions made by `reflaxe.ocaml`;
- assess the boundary between ordinary Haxe-authored `hxhx` core code and
  Reflaxe backend/plugin APIs;
- evaluate promotion feasibility and typed-AST ownership without guessing the
  framework API.

Prefer framework source, public docs, examples, and license. Exclude dependency
caches and generated outputs.

### 5. Optional pressure test: `reflaxe.elixir`

Repository/pin:

- `https://github.com/fullofcaffeine/reflaxe.elixir`
- exact promotion-pilot pin:
  `5b322236e0627f8322394e819cf28ba6c1271a83`

Purpose:

- inspect the real Reflaxe compiler workload used by promotion proofs;
- test whether builtin/plugin/host-adapter recommendations survive a non-toy
  target;
- compare target-core packaging assumptions.

This repository is a pressure test, not a Haxe semantic authority. A selective
upload of its README/docs, compiler source, target runtime, promotion-related
scripts, and todo-app Haxe input is enough. Exclude dependencies, build output,
and generated target snapshots unless a finding specifically needs them.

### 6. Optional testing-pattern reference: `haxe.elixir.codex`

Local/reference repository:

- local checkout name: `haxe.elixir.codex`
- remote repository: `https://github.com/fullofcaffeine/reflaxe.elixir`
- reviewed local reference commit:
  `979a6b7f00856ab50749fa74c4d94a6bbbefc617`

This is the same repository family as the pinned promotion workload above, at
a newer development revision and with a different review purpose. Do not
upload two whole copies. Use the exact old pin for reproducible promotion-path
analysis and only the listed current-revision files for testing-pattern
analysis.

Purpose:

- compare Haxe-authored runtime stdlib test organization;
- compare stdlib inventory/drift reporting;
- compare snapshot versus runtime-semantics evidence;
- evaluate whether the post-Full1 stdlib beads are well shaped.

Do not upload this roughly 1.2 GB working directory wholesale. Upload only the
testing-pattern subset:

- `AGENTS.md`, `README.md`, and `package.json`;
- `scripts/test-haxe-exunit-stdlib.sh`;
- `scripts/stdlib-parity-report.sh`;
- `scripts/ci/check-stdlib-parity-report.sh`;
- `docs/03-compiler-development/TESTING_INFRASTRUCTURE.md`;
- `docs/04-api-reference/STDLIB_SUPPORT_MATRIX.md`;
- `docs/08-roadmap/stdlib-parity/**`;
- `test/haxe_exunit/stdlib_parity/src_haxe/**`;
- `test/upstream_unitstd/README.md`;
- the minimal ExUnit harness files referenced by those scripts.

This is a pattern reference only. Do not import its target-specific semantics or
copy its tests into `hxhx`.

## Main-repo curated fallback

If the client cannot accept the full tracked `hxhx` archive, create a curated
first-pass bundle with these paths:

### Always include

- `AGENTS.md`
- `README.md`
- `LICENSE`
- `package.json`
- `haxe_libraries/**`
- `.beads/issues.jsonl`
- `.github/workflows/**`
- `docs/00-project/**`
- `docs/01-getting-started/**`
- `docs/02-user-guide/**`
- `docs/benchmarks/**`
- `packages/hxhx-core/src/**`
- `packages/hxhx/src/**`
- `packages/hxhx-macro-host/src/**`
- `packages/reflaxe.ocaml/src/**`
- `packages/reflaxe.ocaml/std/**`
- `packages/reflaxe.ocaml/README.md`
- `scripts/ci/**`
- `scripts/hxhx/**`
- `scripts/release/**`
- `scripts/vendor/fetch-haxe-upstream.sh`
- `scripts/vendor/fetch-reflaxe-elixir-upstream.sh`
- `workloads/**`
- `examples/**`

### Include representative tests

- upstream runner/contract tests referenced by active Full1 beads;
- `test/portable/**`;
- plugin/promotion fixtures;
- Stage3/macro runtime tests;
- Cpp and source-native backend smoke/bench source;
- release/performance evaluator fixtures.

If a manual selection is error-prone, include all tracked `test/**` source and
configuration files and remove generated `out/**`/`intended/**` snapshots first.

### Omit first when reducing size

1. committed generated OCaml under `packages/hxhx/bootstrap_out/**` and
   `packages/hxhx-macro-host/bootstrap_out/**`;
2. generated snapshot `out/**` and `intended/**` trees;
3. large historical attribution detail in
   `docs/00-project/CPP_RENDER_TYPE_FLOW_PLAN.md` after retaining its current
   policy/frontier sections;
4. historical closed-bead comments only after retaining complete issue status,
   dependencies, descriptions, and acceptance criteria.

When omitting committed bootstrap/snapshot output, keep
`docs/00-project/MEGA_FILE_GRAVITY_WATCH.md`, regeneration scripts, source
manifests, and the size facts in the controlling prompt so the reviewer can
still assess artifact gravity.

## Exclude from every upload

Do not upload:

- `.git/**` or repository object databases;
- `node_modules/**`, `.haxelib/**`, Lix caches, opam switches, or vendored
  dependency caches;
- `.tmp/**`, `.artifacts/**`, transient `out/**`, compiler build directories,
  and retained gate worktrees/logs;
- the dirty ignored `vendor/haxe/**` or `vendor/reflaxe-elixir/**` worktrees;
- `.env*`, credentials, API keys, tokens, signing material, or private machine
  configuration;
- local editor state;
- core dumps or profiling dumps;
- existing `repomix-output*`, zip archives, backups, or generated review
  bundles;
- unrelated sibling repositories from the workspace.

The main repo's `.beads/issues.jsonl` is required planning data. Review it for
private operational details before an upload outside the intended private GPT
session, but do not omit it from this plan review without replacing it with a
complete active/closed dependency export.

## Repositories not recommended for the first review

Do not upload `haxe.rust`, `haxe.go`, `haxe.ruby`, workspace backups, or other
target experiments in the first pass. They add substantial target-specific
noise without deciding the `hxhx`/`reflaxe.ocaml` critical path.

Add one only if GPT-5.6 Pro identifies a specific cross-target API or testing
question that cannot be answered from `hxhx`, Reflaxe, upstream Haxe 4.3.7,
the pinned `reflaxe.elixir` workload, and the selective Elixir testing-pattern
reference.

## Suggested upload sets

### Best review quality

1. controlling prompt;
2. full tracked `hxhx` archive;
3. clean upstream Haxe 4.3.7 archive;
4. Reflaxe 4.0.0-beta source/docs at `430b4187`;
5. pinned selective `reflaxe.elixir` pressure-test subset;
6. selective `haxe.elixir.codex` stdlib-testing subset.

### Balanced first pass

1. controlling prompt;
2. curated `hxhx` bundle;
3. Reflaxe 4.0.0-beta source/docs at `430b4187`;
4. upstream Haxe 4.3.7 repository link/tag plus suite/module inventory;
5. pinned selective `reflaxe.elixir` subset.

### Minimum viable review

1. controlling prompt;
2. full tracked `hxhx` archive, or the curated fallback;
3. Reflaxe 4.0.0-beta source/docs at `430b4187`.

The minimum set can audit internal coherence, but conclusions about upstream
architecture, suite scope, and real Reflaxe promotion workloads should be
marked lower confidence.

## Label the uploads clearly

Use names that preserve repository and revision identity, for example:

- `hxhx-2ca1eaae.zip`
- `haxe-4.3.7.zip`
- `reflaxe-4.0.0-beta-430b4187.zip`
- `reflaxe-elixir-5b322236-selective.zip`
- `haxe-elixir-codex-979a6b7f-stdlib-testing-selective.zip`

Do not merge different repositories into one unlabeled text dump. Repository
boundaries matter to provenance and semantic authority.

## First message to GPT-5.6 Pro

After uploading, send:

> Follow `GPT_5_6_PRO_WHOLE_REPO_REVIEW_PROMPT.md` as the controlling task and
> output contract. Inspect the uploaded repositories directly. Treat upstream
> Haxe 4.3.7 as a behavior/architecture oracle only, Reflaxe as a framework
> dependency reference, and sibling targets as pressure tests. Do not provide
> implementation code for transcription. If context prevents complete
> coverage, state exactly what was inspected and request the smallest missing
> bundle before finalizing plan changes.

## Handling the response

Do not apply GPT's proposed plan automatically.

1. Save the complete response with model/date/repository revisions.
2. Verify every cited bead, workflow, file, and claimed dependency.
3. Separate accepted findings from rejected or deferred recommendations.
4. Apply bead status/dependency/scope changes only after the project owner
   approves any changed Full1, release, provenance, or north-star boundary.
5. Update README/North Star wording only when verified evidence changes public
   production readiness.
6. Preserve the response as architecture guidance, not a source-code donor.
