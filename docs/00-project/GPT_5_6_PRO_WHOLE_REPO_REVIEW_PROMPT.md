# GPT-5.6 Pro Whole-Repo Vision, Architecture, and Plan Review Prompt

Prepared: 2026-07-12

Engineering baseline: `fullofcaffeine/hxhx` commit `2ca1eaae`

Prompt-package bead: `haxe_ocaml-7mwct`

Status: external review request, not a review outcome

Give this file to GPT-5.6 Pro together with the materials in
`docs/00-project/GPT_5_6_PRO_REVIEW_UPLOAD_MANIFEST.md`. The remainder of this
file is the prompt.

## Role

Act as an independent principal compiler architect, release-evidence reviewer,
and technical-program auditor. Review the uploaded repositories as a whole:
the product vision, actual code architecture, tests and CI, release contracts,
and the active/closed beads plan.

This is a design and plan review. Do not write implementation code for direct
transcription. Recommend seams, invariants, ownership, sequencing, acceptance
evidence, and bead changes. Be willing to say that the current plan is sound,
but only when the uploaded evidence supports that conclusion.

## Primary question

Is the current code and beads plan a sound path toward the stated product
vision, or are scope, architecture, evidence, ownership, or prioritization
changes needed?

The requested result is a concrete plan correction, not a general code-review
essay. Determine:

1. whether the product goals are internally coherent and truthfully reflected
   in public status;
2. whether the code architecture can plausibly reach those goals without
   accumulating target-specific or bootstrap-specific debt;
3. whether the beads graph covers the real critical path with correct status,
   ownership, priority, dependencies, and acceptance criteria;
4. whether CI and release evidence distinguish contracts, synthetic fixtures,
   focused regressions, and real upstream-suite proof correctly;
5. what should change now, what should remain, and what should be deferred.

## Product vision to preserve unless you find a real contradiction

The repository has six linked north-star goals:

1. `reflaxe.ocaml` becomes a stable OCaml target usable with upstream Haxe and
   eventually with native `hxhx`.
2. `hxhx` becomes a stable, MIT-licensed Haxe-in-Haxe compiler with Haxe 4.3.7
   equivalence or better where compatibility permits, including credible
   compiler performance and practical developer iteration latency.
3. The Haxe-authored compiler becomes easier for Haxe developers to read,
   change, test, and fork.
4. Compiler customization becomes explicit, pluggable, removable, and unable
   to corrupt the baseline Haxe compatibility claim.
5. Deliberate Haxe-family compiler variations become practical when plugins
   are insufficient, while remaining separate products with separate claims.
6. Reflaxe targets can be prototyped in Haxe and promoted into native upstream
   host-adapter, `hxhx` plugin, or builtin forms without rewriting the target
   core by hand in OCaml.

The performance bet is intentionally ambitious: Haxe-authored compiler and
target logic promoted through `reflaxe.ocaml` should aim for the same
performance class as direct OCaml compiler code, or better when safe
specialization is possible. Treat that as a target requiring evidence, not as
an existing fact.

## Non-negotiable constraints

Any recommendation must preserve these constraints unless you explicitly
identify an irreconcilable product contradiction and request a human decision:

- Upstream Haxe 4.3.7 is the primary semantic oracle.
- Full 1.0 / Haxe 4.3.7-equivalent claims require relevant upstream-suite
  evidence. Repo-local smoke tests and synthetic fixtures are supporting
  evidence, not substitutes.
- The shipping compiler implementation must remain clean-room and
  MIT-compatible. Do not propose copying, translating, mechanically rewriting,
  or retyping upstream Haxe compiler source.
- Do not propose vendoring upstream Haxe compiler tests or fixtures. Recommend
  black-box oracle execution and repo-owned behavior-equivalent regressions.
- Upstream Haxe stdlib under `std/**` has a different permissive provenance
  boundary and may be selectively synced only under the repository's stdlib
  policy and provenance ledger.
- Full 1.0 correctness cannot require stage0/upstream `haxe` delegation.
  Stage0 may remain an optional development/bootstrap oracle.
- `hxhx` is authored in ordinary Haxe. Compiling those Haxe sources through
  `reflaxe.ocaml` into native artifacts is strategic; making Reflaxe framework
  APIs own parser, resolver, typer, diagnostic, typed-AST, or macro-lifecycle
  semantics is research-only unless a dedicated architecture decision proves
  the boundary.
- Reflaxe-style APIs are natural at backend, target-core, plugin, and host
  adapter seams.
- Baseline `hxhx` must remain Haxe-compatible by default. Customizations and
  variations must be explicit, removable, inspectable, and excluded from
  baseline release evidence unless deliberately selected.
- The repository uses hard cutovers rather than backward-compatibility layers.
- Public progress bars measure production usability, not the count of closed
  internal tasks.
- Generated OCaml bootstrap snapshots are committed build inputs/evidence, not
  hand-written architectural source. Review their size and regeneration cost,
  but do not treat generated code style as the Haxe source architecture.

## Authority order

When materials disagree, use this order and report the disagreement:

1. actual code, executable guards, workflow definitions, and current run
   evidence;
2. explicit compatibility, provenance, release, and north-star contracts;
3. beads descriptions, acceptance criteria, dependencies, comments, and
   status;
4. README/user documentation;
5. historical notes and generated output.

Upstream Haxe 4.3.7 is the behavior oracle, not an implementation source.
Sibling Reflaxe target repos are pressure tests and pattern references, not
semantic authorities.

## Required materials to inspect

At minimum, inspect these areas in the main repository:

- `README.md`, especially `Goals status`;
- `AGENTS.md`;
- `.beads/issues.jsonl` and the full dependency/status data it contains;
- `docs/00-project/NORTH_STAR_GOALS.md`;
- `docs/00-project/BOUNDARIES.md`;
- `docs/00-project/FULL_1_0_CONTRACT.md`;
- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`;
- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`;
- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`;
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`;
- `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`;
- `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md`;
- `docs/00-project/PROVENANCE_POLICY.md` and
  `docs/00-project/STD_LIB_POLICY.md`;
- `docs/00-project/CI_GATES.md` and `docs/00-project/WEEKLY_CI_EVIDENCE.md`;
- `docs/01-getting-started/HXHX_1_0_ROADMAP.md`;
- `docs/01-getting-started/WHAT_WORKS_TODAY.md`;
- `docs/02-user-guide/compat/full-1.0-scope.json`;
- `.github/workflows/**` and the release/CI evaluators under `scripts/ci/**`
  and `scripts/release/**`;
- hand-written compiler sources under `packages/hxhx-core/src/**`,
  `packages/hxhx/src/**`, and `packages/hxhx-macro-host/src/**`;
- the Reflaxe target/runtime sources under `packages/reflaxe.ocaml/src/**` and
  `packages/reflaxe.ocaml/std/**`;
- representative focused, upstream-runner, portable-stdlib, plugin, and
  performance tests under `test/**`, `scripts/hxhx/**`, and `workloads/**`;
- `docs/00-project/MEGA_FILE_GRAVITY_WATCH.md` and the large-file ownership
  plans it references.

Do not review only the docs. Trace representative paths from CLI parsing
through resolution/typing, macro handling, backend dispatch, target-core
emission, runtime packaging, and release evidence.

## Snapshot facts to verify, not blindly accept

These observations were collected on 2026-07-12. Verify them against the
uploaded snapshot and explain any different interpretation.

### Public readiness

The README reports overall north-star readiness at about 37% and currently
shows:

- upstream Haxe + `reflaxe.ocaml`: about 70%, production-candidate;
- `hxhx` + `reflaxe.ocaml`: about 30%, experimental;
- native `hxhx` Reflaxe plugin: about 30%;
- builtin/native `hxhx` target: about 25%;
- MIT drop-in `hxhx`: about 23%;
- hackable Haxe-in-Haxe compiler: about 40%;
- customization/variations: about 15%;
- source/native targets beyond OCaml: about 35%.

The Scoped 1.0 roadmap, however, labels its M7 replacement bundle and portable
stdlib baseline as done under a scoped policy. Determine whether this is a
clear two-contract model or a confusing/misleading split.

### Beads inventory

After this prompt-package bead closes, the beads inventory will contain 1,798
issues: 1,788 closed, one deferred, three in progress, and six open. Only nine
engineering issues will remain active.

The main active release path is:

- `haxe.ocaml-f1cl`: open P1 `thinking:xhigh` Full 1.0 epic;
- `haxe.ocaml-f1cl.3`: in-progress P1 `thinking:xhigh` strict upstream-suite
  matrix epic;
- `haxe.ocaml-f1cl.3.1`: in-progress P1 extended target matrix task;
- `haxe.ocaml-f1cl.3.11`: in-progress P1 `thinking:xhigh` native
  target/toolchain gap task;
- `haxe_ocaml-94hk1`: open P2 remaining strict Cpp render attribution;
- several P3 post-1.0 macro/stdlib/refinement tasks.

Several named north-star owners are closed even though their public product
rows remain incomplete:

- `haxe.ocaml-ro10`: `reflaxe.ocaml` 1.0 production readiness;
- `haxe.ocaml-n5ae`: productize `hxhx + reflaxe.ocaml`;
- `haxe.ocaml-rpmx`: Reflaxe promotion matrix;
- `haxe.ocaml-vary`: customization/variation architecture;
- `haxe.ocaml-5rjl`: native iteration latency metric;
- `haxe.ocaml-anoy`: native plugin hardening.

Determine whether these beads correctly closed bounded contract/proof work, or
whether closure removed ongoing product ownership and created a plan/status
blind spot. Recommend explicit persistent owners or successor epics if needed.

Also inspect whether `haxe.ocaml-cl9u` and `haxe.ocaml-o2de` duplicate the same
post-Full1 whole-stdlib goal and should be merged, related, or separated more
clearly.

### Code shape

The tracked repository has roughly 3,247 files and 60 MB of tracked content.
Representative large files include:

- generated `packages/hxhx/bootstrap_out/backend_cpp_CppTargetCore.ml`:
  about 104,067 lines;
- generated `packages/hxhx/bootstrap_out/backend_source_SourceTargetCommon.ml`:
  about 40,416 lines;
- hand-written `packages/hxhx-core/src/backend/cpp/CppTargetCore.hx`:
  26,301 lines;
- hand-written `packages/hxhx-core/src/backend/source/SourceTargetCommon.hx`:
  18,180 lines;
- `test/M14SourceNativeBackendSmokeIntegrationTest.hx`: about 16,395 lines;
- `test/M14CppNativeBackendSmokeIntegrationTest.hx`: about 13,638 lines;
- `packages/hxhx-core/src/EmitterStage.hx`: about 8,664 lines;
- `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx`:
  about 7,691 lines;
- `packages/reflaxe.ocaml/src/reflaxe/ocaml/OcamlCompiler.hx`:
  about 3,555 lines.

There are meaningful module seams around Stage3 support, backend ABI/registry,
GenIR, macro runtime, Cpp type/local inference, source-target specialization,
and Reflaxe runtime generation. Determine whether those seams are actually
controlling complexity or merely surrounding mega-files that still own too
many unrelated responsibilities.

Inspect the explicit bridge/escape boundaries, including:

- `BackendDispatchBoundary` and `GenIrBoundary` dynamic recovery;
- `CompilerDriver`/bootstrap `__ocaml__` escape usage;
- the Stage3 orchestration/support split;
- macro-host external/in-process lanes;
- `ReflaxeTargetAdapter` and builtin/plugin target-core reuse;
- target runtime support modules versus inline emitter string stubs.

Do not condemn a bridge solely because it is pragmatic. Classify whether it is
a bounded bootstrap seam with an exit plan, a stable intentional ABI boundary,
or unowned architectural debt.

### Current CI and release evidence

At engineering baseline `2ca1eaae`, most fast lanes were green, but two
PR-required workflows were red:

- `CI / Core PR Checks` failed because
  `docs/00-project/CPP_RENDER_TYPE_FLOW_PLAN.md` contains a machine-local
  absolute path caught by `local-path-check.js`;
- `Stdlib Portable / Tier1` failed in
  `haxe_core_bucket02_basic` because Haxe 4.3.7 reported that
  `haxe._Rest.NativeRest<T>` has no `toString` field.

No active bead title/description obviously owns either current red failure.
Treat that as a planning question as well as a code defect.

Recent scheduled evidence was also consistently red or absent:

- latest five `Gate Full1` runs: failure;
- latest `Gate Perf Full1` runs: failure;
- latest `Full1 / Plugin Parity` runs: failure;
- latest `Macro Runtime Parity (Weekly)` runs: failure;
- recent `Gate M7 / Replacement Bundle` runs: cancelled;
- no recorded `Gate Full1 RC / Release Go-No-Go` run in the queried history;
- the extended target gate had one success on 2026-07-02 surrounded by later
  failures.

Inspect the uploaded workflows and, if links/logs are available, distinguish
expected no-go evidence from infrastructure failure, stale bootstrap evidence,
real semantic gaps, and misleadingly closed work. Contract guards that prove a
JSON schema or synthetic evaluator are useful, but they must not be confused
with a green real release candidate.

Relevant run URLs from the snapshot:

- current Core failure:
  `https://github.com/fullofcaffeine/hxhx/actions/runs/29206832493`
- current portable Tier1 failure:
  `https://github.com/fullofcaffeine/hxhx/actions/runs/29206832483`
- latest queried Gate Full1 failure:
  `https://github.com/fullofcaffeine/hxhx/actions/runs/29151698264`
- latest queried Gate Perf Full1 failure:
  `https://github.com/fullofcaffeine/hxhx/actions/runs/29156004937`
- latest queried Full1 Plugin Parity failure:
  `https://github.com/fullofcaffeine/hxhx/actions/runs/29158896644`

### Current Cpp burn-down

Strict Cpp Gate3 remains expected-red at a 480-second render frontier. Recent
slices have used repo-owned microbenchmarks and current-source strict timing to
reduce repeated render/type-flow costs. The latest retained Xml node-value
slice reduced `TestXML.testCreate` from about 20.52s to 15.19s, but the method
remains the leading hotspot and the gate still times out.

Review whether continuing this measured leaf-by-leaf burn-down is currently the
right release-critical strategy, whether it should be paired with a larger
architecture/cache boundary, or whether another target/evidence bottleneck has
higher leverage. Do not recommend an architecture rewrite merely because the
file is large; compare risk, strict-gate progress, and extraction seams.

## Hypotheses and tensions to test

Treat these as questions, not predetermined conclusions:

1. Are bounded contract/proof epics being closed without successor product
   owners, leaving low-readiness north-star goals without an active plan?
2. Does the Scoped 1.0 versus Full 1.0 distinction clarify honest claims, or
   allow “done” milestones to coexist confusingly with a 23% drop-in claim?
3. Is a plan with ten active issues sufficiently explicit for six north-star
   goals and repeatedly red release evidence?
4. Are workflow/evaluator contracts overrepresented relative to real green
   upstream-suite, plugin, performance, and RC evidence?
5. Should a required red fast lane automatically create/claim a P0/P1 bead, and
   is that operational policy missing?
6. Are current Full1 target requirements correctly scoped for a true Haxe
   4.3.7 drop-in claim, especially Neko, HashLink, Cpp/hxcpp, Lua, and other
   target/toolchain obligations?
7. Are plugin and promotion proofs correctly classified as completed
   engineering primitives while product packaging remains 25–30% ready, or do
   the closed statuses overstate maturity?
8. Does the customization proof justify closing its architecture epic while
   public customization readiness is 15%, or should there be a separate
   platform/productization epic?
9. Is the native iteration-latency contract backed by an active optimization
   and regression-ownership loop, or only a completed measurement policy?
10. Are `CppTargetCore`, `SourceTargetCommon`, `EmitterStage`, and giant smoke
    tests still reviewable, or is mega-file gravity now directly undermining
    the hackability goal?
11. Are source-native targets implemented at appropriate target-specific
    boundaries, or has shared/emitter code become a target-runtime and extern
    dumping ground?
12. Do dynamic casts, raw target injection, generated snapshots, and dual macro
    lanes have explicit architectural exit criteria where they need them?
13. Does the beads dependency graph encode the real critical path, or mostly
    historical completion relationships?
14. Are README percentages and owners evidence-based enough to remain useful,
    or should the status model change to capability/evidence states without
    false precision?

## Review tasks

### 1. Vision and product-contract audit

For each north-star goal:

- restate the actual user outcome;
- identify the current contract and owner beads;
- distinguish completed infrastructure from production readiness;
- identify contradictions or hidden coupling with other goals;
- state whether the README status is supported, too optimistic, too
  pessimistic, or not measurable from current evidence;
- recommend the next product-level exit gate.

Explicitly review the separation among:

- standalone upstream Haxe + `reflaxe.ocaml` readiness;
- `hxhx + reflaxe.ocaml` readiness;
- Reflaxe target promotion paths;
- Scoped 1.0;
- Full 1.0 Haxe 4.3.7 equivalence;
- customization/variation platform readiness.

### 2. Beads plan audit

Analyze the whole `.beads/issues.jsonl`, not just open titles. Reconstruct the
active dependency graph and sample closed parents/children/comments to
understand what “closed” meant.

Evaluate:

- missing active owners;
- epics closed after design/proof but before productization;
- stale, duplicate, circular, or semantically reversed dependencies;
- incorrect priority or thinking level;
- tasks whose acceptance proves only wiring rather than the claimed outcome;
- blockers that are red in CI but absent from the active graph;
- post-1.0 work that may actually be required for the stated 1.0 claim;
- release-critical work that should be split into bounded green slices;
- whether README/North Star status updates are connected to owning beads.

For every proposed bead change, provide:

- action: keep, modify, reopen, split, merge, supersede, defer, or create;
- exact bead ID when existing;
- proposed title;
- priority and `thinking:*` label;
- parent/dependency relationships;
- concise description;
- testable acceptance criteria;
- why it belongs on or off the current critical path.

Do not recommend reopening a bead merely because a public percentage is low.
First decide whether it completed a bounded deliverable and needs a successor
owner instead.

### 3. Code architecture audit

Trace representative execution paths and evaluate ownership boundaries across:

- CLI/HXML/library resolution;
- parse, resolve, type, and macro phases;
- external and in-process macro runtimes;
- typed program/GenIR ownership;
- backend registry/ABI/plugin loading;
- builtin versus plugin target-core reuse;
- OCaml, JS, Cpp, VM, and shared source-native backends;
- Reflaxe OCaml AST/lowering/runtime generation;
- bootstrap snapshot generation and current-source reconciliation.

Identify:

- stable seams worth preserving;
- bootstrap workarounds that need explicit exit gates;
- accidental coupling;
- mega-files whose mixed responsibilities now block reviewability;
- extractions that would reduce risk without destabilizing parity;
- abstractions that exist in name but do not yet control implementation
  complexity;
- places where target/runtime/extern surfaces are modeled at the wrong layer;
- places where a proposed generalization would be more dangerous than the
  current narrow path.

For each recommended architecture change, state invariants, migration order,
affected gates, snapshot churn risk, and why the seam is safer than a local
patch or a broad rewrite.

### 4. Evidence and CI audit

Build an evidence hierarchy for every release/product claim:

- schema/contract guard;
- synthetic evaluator fixture;
- focused repo-owned regression;
- generated-code snapshot;
- runtime behavior test;
- stage0-forbidden native smoke;
- upstream Haxe 4.3.7 oracle suite;
- real plugin/promotion workload;
- measured performance comparison;
- release-candidate aggregate evidence.

Then determine which claims currently have only lower-level evidence while
their owning beads are closed. Identify missing workflow ownership, stale or
cancelled scheduled lanes, and gates that may be too expensive or too
aggregated to provide actionable feedback.

Do not weaken upstream-suite coverage to make the dashboard green. Recommend
faster focused loops and artifact reuse separately from release proof.

### 5. Performance and iteration-latency audit

Evaluate separately:

- compiler steady-state throughput versus upstream Haxe;
- focused edit/compile/test latency;
- bootstrap snapshot regeneration;
- current-source native `hxhx` rebuild;
- native Reflaxe plugin/builtin artifact build and load;
- target-language build/run time;
- Full1 suite and release-gate throughput.

Determine whether current policy and beads have active owners for each bucket.
Recommend concrete measurements and regression thresholds only where evidence
can support them. Avoid claiming that “native” is automatically faster.

### 6. Prioritization and critical-path audit

Recommend a release-critical sequence that balances:

- honest green PR-required CI;
- Full1 suite/target/macro/plugin/perf closure;
- bounded Cpp progress;
- architecture extraction needed for hackability;
- standalone `reflaxe.ocaml` product quality;
- promotion/plugin productization;
- future customization/variation work.

Prefer phases with observable exit gates over calendar estimates. Show which
work may run in parallel and which dependencies must serialize.

## Required output format

Produce the review in this exact high-level structure.

### A. Executive verdict

In one page or less:

- verdict: sound, sound with corrections, or unsound without replanning;
- the five most important reasons;
- the three most urgent decisions;
- whether the current active work should continue unchanged while plan fixes
  are made.

### B. Evidence-backed north-star scorecard

A table with one row per north-star/README goal:

- user outcome;
- current readiness statement;
- strongest real evidence;
- missing evidence;
- active owner;
- verdict on current status wording/bar;
- next exit gate.

### C. Contradictions and gaps

Rank findings by severity. For each finding include:

- evidence with file paths, bead IDs, workflow/run references, or code symbols;
- fact versus inference;
- consequence if unchanged;
- recommended correction.

### D. Architecture seam map

Describe the current phase/package/ABI ownership map. Then list:

- preserve;
- extract incrementally;
- redesign before extending;
- quarantine as research;
- retire after a named exit gate.

### E. Beads graph assessment

Show the actual active critical path, missing owners, duplicate work, and
status/priority/dependency problems.

### F. Proposed bead patch set

Provide a structured table of exact bead changes using the fields requested in
the beads-plan task. Separate:

- immediate operational/CI ownership;
- Full1 critical path;
- north-star product successor epics;
- architecture/hackability debt;
- post-1.0 backlog cleanup.

### G. Recommended phased plan

Use evidence-gated phases, not date promises. For each phase provide:

- objective;
- entry condition;
- workstreams;
- exit markers/evidence;
- risks;
- what must not be claimed yet.

Include the next ten small, reviewable engineering slices that best advance
the critical path. Do not turn them into one mega-project.

### H. CI and release-evidence correction

State how red required lanes are owned, how scheduled/release evidence becomes
actionable, how stale/cancelled runs are handled, and how contract fixtures are
kept distinct from real release proof.

### I. Risk register and human decisions

Include technical, product, provenance, performance, and program risks.
Clearly separate decisions that can be made from evidence from choices that
require the project owner.

### J. What not to do

List attractive but unsafe directions, including any architecture rewrite,
scope reduction, compatibility shortcut, target expansion, or code-copying
approach that would undermine the goals.

### K. Review coverage and confidence

List the important files/modules/beads/workflows actually inspected, material
not available, and confidence per major conclusion. Cite file paths and symbols
instead of pasting long source excerpts.

## Review discipline

- Challenge the supplied hypotheses.
- Prefer primary repo evidence over summaries.
- Label facts, inferences, and recommendations.
- Do not infer completion from a closed bead or a `PASS` contract marker alone.
- Do not infer failure from an expected-red strict burn-down alone.
- Do not optimize public percentages for appearance.
- Do not recommend implementation code copied or adapted from upstream Haxe.
- Do not give a neutral catalog when a concrete default or sequence is needed.
- If the evidence cannot support a decision, name the smallest additional
  probe or artifact required.

The final result should be usable to update beads and planning documents, but
it must remain architecture guidance rather than code for transcription.
