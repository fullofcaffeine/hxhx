# Oracle Checkpoint: Six-Month Architecture And Roadmap

Prepared: 2026-07-23

Status: GPT-5.6 Pro review accepted with local corrections; roadmap and tracker
sequencing updated; no implementation or readiness claim

Owning disposition Bead: `haxe_ocaml-m2d64`

Review-package Bead: `haxe_ocaml-vjyxo` (closed after preparing the package;
it did not own response implementation)

Review provenance:

- reviewed candidate:
  `26796665e5ae7c4483de9f74a63650dab3a8cf89`;
- outer package SHA-256:
  `35faa41a65167fe2818c1f2a9b778b691fc1ae94c5ac4dcc4058ac5372e95d78`;
- controlling prompt SHA-256:
  `e2aa503a81b13a4dc7631079140e6980d09ba9a7a293bd3f5e11b862ca236506`;
- reviewer: GPT-5.6 Pro;
- review date: 2026-07-23.

The reviewer reported that the internal package manifest passed, all 131 unique
cited path/range references resolved, and focused architecture and evidence
guards passed. Those checks establish package integrity and citation
availability. They do not by themselves prove the report's interpretations,
runtime behavior, current remote CI health, or release readiness.

The reviewer did not rerun the multi-hour upstream suites, complete bootstrap,
macro/eval, cross-platform package, compiler-scale performance, or hosted CI
workflows. The report correctly treats their committed receipts as historical
evidence bound to their recorded candidate, not as current-candidate release
evidence. This disposition makes the same distinction.

## Outcome

The project direction remains valid and does not need a whole-compiler rewrite.
The roadmap was longer than necessary because the native `hxhx` OCaml route and
standalone `reflaxe.ocaml` currently contain two different implementations that
decide how Haxe behavior becomes OCaml.

A **semantic owner** means the component that decides observable program
behavior. For example, it decides whether an assignment evaluates a receiver
once or twice, which conversion a call performs, or which runtime helper is
required. Giving the same identifier to two components does not make them one
semantic owner.

The current high-level shape is:

```text
upstream Haxe -> standalone reflaxe.ocaml lowering -> OcamlExpr -> OCaml

native hxhx -> OcamlTargetCore -> Stage3 EmitterStage -> OCaml
```

`OcamlTargetCore` currently delegates to `EmitterStage.emitToDir`. The Stage3
emitter still owns OCaml-specific representation choices, recursive-group
construction, compatibility shims, generated-file rewrites, placeholder
modules, and selected fallback values. It remains useful for bootstrap and
diagnosis, but it is not the standalone target implementation and cannot prove
that one Reflaxe target core serves both hosts.

The direct implementation evidence is
`packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx:11-25,48-107`.
Representative Stage3 bring-up behavior is visible in
`packages/hxhx-core/src/EmitterStage.hx:6698-6714,7815-7830,8036-8049,8540-8666`.

The accepted destination is:

```text
upstream Haxe facts ----\
                         -> one standalone reflaxe.ocaml target core -> OCaml
native hxhx facts ------/
```

The host adapters may translate stable typed facts and transport. They may not
select different target behavior, repair generated OCaml, or invoke a second
lowerer.

## Soundness Review

### Findings accepted

The following findings match the live repository:

1. **The shared OCaml target is not yet shared in implementation.**
   `packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx` installs an
   `EmitterStage` plan and calls `EmitterStage.emitToDir`. The shared core ID is
   therefore a useful intended identity, not convergence proof.
2. **Stage3 still contains bring-up repairs.**
   `packages/hxhx-core/src/EmitterStage.hx` patches generated modules, emits
   placeholder XML surfaces, contains fallback values, and computes target
   ordering inside emission. These behaviors are visible and explicitly
   described as bring-up work in several source comments.
3. **Standalone `reflaxe.ocaml` has the right architectural direction but
   incomplete semantic coverage.** The accepted target-specific lowered model,
   stable identities, validators, and semantic-free printer boundary remain the
   correct destination. Representation/storage/capture, calls/conversions,
   control effects, and runtime authority are the next connected families.
4. **Post-Full1 products were active too early.** M22 and customization are
   already documented as post-Full1 planning with Full1 and authentic
   `hxhx + reflaxe.ocaml` prerequisites, while their parent or design Beads were
   still marked active.
5. **Native typed-module reuse is not ready.** Source, lookup, and parser reuse
   can proceed. Reusing typed modules must wait for deterministic local
   identity, request-owned mutable state, complete dependency observation,
   clean-versus-warm comparison, failure/reset evidence, and bounded memory.
6. **Compatibility work needs root-family ownership.** A sequence of target
   patches that only reaches the next compiler error is useful diagnosis but
   cannot be counted as a shrinking semantic gap unless the owning model and
   regression evidence also improve.
7. **The current evidence policy is broadly sound.** Same-candidate receipts,
   risk-routed CI, provenance checks, and the bootstrap watchdog are useful
   foundations. A policy or inventory pass remains lower evidence than a real
   compile, run, package, or compatibility result.

### Corrections to the review

The review is guidance, not authority. These statements are narrowed before
adoption.

#### Stage3 consumes a typed projection, not the original parsed body

`TypedModule.getBackendDeclaration()` is built by `TypedBodySource` from the
structural typed tree. `EmitterStage` uses that source-shaped projection for
many current lowering decisions. Calls to `TypedModule.getParsed()` in the
relevant path provide file/source provenance.

The governing typed-body contract is explicit at
`packages/hxhx-core/src/TypedModule.hx:1-9,67-79` and
`packages/hxhx-core/src/TypedBodySource.hx:1-8`; representative backend
consumption is at `packages/hxhx-core/src/EmitterStage.hx:5955-5963,6762-6778`.

The remaining problem is still real: the backend converts typed facts back into
a source-shaped representation and independently performs OCaml lowering.
However, describing this as rereading the original parser body would erase a
completed and important typed-body cutover.

#### `Obj.magic` is not universally forbidden

OCaml sometimes needs a deliberate unsafe representation boundary for dynamic
Haxe values or native interop. A reviewed use can remain when its source and
target types, representation reason, permitted profile, validation, and tests
are explicit.

The prohibited cases are placeholder values, unexplained casts, silent
fallback, or uses that allow unsupported source behavior to keep compiling.
The Stage3 hard-cut guard must distinguish those from an admitted typed
boundary.

#### README percentages stay until an evidence-backed status update

The README already places a maturity label beside every percentage and says the
numbers are coarse, editorial, and non-additive. The maintainer has explicitly
asked to retain percentage numbers.

This review changes sequencing, not capability. It therefore does not change a
bar or percentage. A later evidence-backed update may use a numeric range
instead of false precision, but it must still retain a percentage signal and a
dominant maturity label.

#### Stress counts and latency budgets are provisional

A seeded 10,000-edit clean-versus-warm differential is accepted as a scheduled
typed-cache admission test because one stale result is a correctness failure.
It is not the only proof and does not replace designed dependency fixtures.

The review's absolute p95 latency numbers are starting hypotheses. They do not
become release gates until representative workloads, a fixed machine class,
raw samples, and noise analysis show that the budgets are realistic. The
relative rule applies now: reuse must improve the complete user request after
identity and invalidation work is included.

#### Bootstrap watchdog safety and bootstrap performance are separate

`haxe_ocaml-xm503` already closed the watchdog defect. A **watchdog** is the
safety monitor that distinguishes a slow but progressing compiler from a
stalled one and, on timeout, stops only the compiler process tree supplied by
the regeneration owner. The current implementation observes accumulated CPU
time, log growth, and process-tree changes for a soft stall limit, while
retaining a separate absolute ceiling. It reports which limit fired and whether
descendant cleanup completed.

That safety design does not make a 14–16 minute forced bootstrap fast.
`haxe_ocaml-xsg6m` now owns performance profiling only: qualify the host,
separate useful phases, retain time/RSS/unit-count samples, and select a bounded
optimization only after the dominant avoidable cost is measured. It does not
reopen the watchdog merely because a healthy compile is slow. The tested
operator explanation remains in `docs/01-getting-started/TESTING.md`.

#### Full1 is not a technical prerequisite for typed-cache development

A typed-cache hit claims that a warm request is equivalent to a clean request
for the same compiler candidate and supported input. It does not claim that the
clean compiler already implements all of Haxe 4.3.7. Stable identities,
complete dependency observations, request isolation, differential tests, and
bounded memory are therefore the direct cache-admission prerequisites.

Typed-cache implementation and opt-in evidence may begin once those direct
gates pass and the work-in-progress cap allows it. Full1 remains necessary for
a Full1 release claim, and a default server used in Full1 evidence must pass the
same-candidate clean-versus-warm matrix. This distinction keeps the server from
caching unchecked facts without postponing high-value iteration work until
every unrelated compatibility target is complete.

#### Tracker triage is not bulk closure authority

The review's 57-item table is useful prioritization advice, but a review cannot
prove that another repository accepted transferred work or that a symptom
reproducer has been absorbed by a root owner. This disposition changes the
critical owners, dependencies, and post-Full1 statuses that are supported by
local evidence. It does not bulk-close, merge, or transfer every listed Bead.

M22 implementation children remain open and non-ready through their explicit
prerequisite chains. The M22 and customization parent records are deferred to
make the portfolio decision visible, but parent status alone is not claimed as
the mechanism that blocks every child. Compatibility leaves remain until their
reproducer and acceptance evidence are explicitly adopted by the root-family
owner. Cross-repository tasks require coordination and a receipt in the
destination repository before ownership changes.

#### The package-preparation Bead was correctly closed

`haxe_ocaml-vjyxo` explicitly owned creation and verification of the review
package, not later response implementation. It remains closed. This document
and `haxe_ocaml-m2d64` own response disposition.

## Decisions

### 1. Keep one product OCaml target implementation

No new Stage3-only OCaml semantic repair may earn standalone
`reflaxe.ocaml` or shared-target product readiness. If a Stage3-generated
artifact is offered as evidence for a declared Full1 behavior, the exact
behavior still has to pass its owning Full1 gate; the repair itself is not
evidence and the OCaml hard cut is not a Full1 prerequisite.

Until the hard cut:

- Stage3 remains a bounded bootstrap and diagnostic lane;
- existing repairs may remain to reproduce and classify gaps;
- new placeholder modules, generated-file semantic rewrites, or unexplained
  fallback values require an explicit root-owner decision and cannot be cited
  as product closure; and
- a green Stage3 workload proves only the behavior that its exact test
  observes, not target-core convergence.

The combined-product owner `haxe_ocaml-38gsp` now has a child dedicated to the
hard cut. That child must route native `hxhx` facts into the actual standalone
target, prove the target and lowered-plan identities, and reject participation
by `EmitterStage`.

### 2. Complete standalone semantic safety before promotion products

The standalone release path is:

```text
validated place/evaluation foundation
  -> representation, storage, and capture
  -> calls and conversions
  -> structured control effects
  -> semantic runtime and output ownership
  -> standalone product aggregate
```

The concrete owners are `haxe_ocaml-9v1va` (completed foundation),
`haxe_ocaml-9bome`, `haxe_ocaml-taef5`, `haxe_ocaml-w32h3`,
`haxe_ocaml-0uwin`, and `haxe_ocaml-s7jry`.

This sequence does not authorize a universal Reflaxe IR, CFG, SSA form, effect
framework, or whole-target rewrite. The OCaml-specific model grows when a
measured correctness, interop, performance, or tooling requirement needs more
power.

### 3. Prove an authentic shared-target hard cut

The hard-cut proof may begin after the standalone semantic prerequisites are
complete. It does not wait for a public Full1 release decision.

The broader `hxhx + reflaxe.ocaml` supported-product claim still requires:

- the standalone target product;
- Full1 evidence for the declared compiler scope;
- clean install/build/run and toolchain provenance;
- documented diagnostics and failure behavior; and
- measured common-loop latency.

### 4. Defer M22 and general customization implementation

The accepted planning contracts remain useful. Implementation is deferred until
Full1 and the authentic shared-target hard cut exist.

This is a sequencing decision, not a rejection of the products. Future M22 and
compiler-transform work should reuse one stable identity, revision, patch,
manifest, and native-artifact substrate rather than independently creating
competing contracts.

### 5. Continue the server in evidence-gated layers

Continue:

- upstream-Haxe/Reflaxe whole-program warm-build correction under
  `haxe_ocaml-850ii.33`;
- native source, lookup, and parser reuse;
- request-state isolation; and
- report-only dependency observation.

Do not enable native typed-module reuse until the new admission child opens all
of these:

- stable lexical local and declaration identities;
- complete dependency observation with no known false negatives;
- deterministic clean-versus-warm edit fixtures plus the scheduled seeded
  stress run;
- no cache or output publication after failure or cancellation;
- reset and worker-state isolation;
- a measured memory plateau and bounded eviction; and
- material end-to-end latency improvement after validation overhead.

### 6. Limit implementation work in progress

Until the shared-target hard cut is complete, maintain no more than three
active P0 implementation fronts:

1. frontend facts, request isolation, and dependency observation;
2. standalone `reflaxe.ocaml` semantic safety; and
3. the current integration or Full1 root-family owner.

Long-lived product outcomes and deferred planning records may remain open, but
they do not authorize simultaneous implementation. Each active front must name
one user outcome, executable gate, stop condition, and successor.

### 7. Classify repeated compatibility failures by root family

The Full1 target coordinator uses these broad families:

- syntax and exact source facts;
- resolution and stable identity;
- typing, operators, places, calls, and conversions;
- macros and generated declarations;
- control effects;
- runtime and standard library;
- target representation and emission; and
- external toolchain or packaging.

After three fixes in one family that only expose another source-shaped target
failure, pause new independent leaves. Preserve the reproducers, review the
shared owner, and explain how the next change reduces the root family rather
than merely moving the first failing line.

## Corrected Convergence Plan

Milestones 1 and 2 may proceed in parallel. Milestone 3 is the hard cut for the
combined `hxhx + reflaxe.ocaml` product. Milestone 4 is the independent Full1
compiler outcome for its already declared target scope; it does not depend on
Milestone 3. Milestone 5 may begin once its direct prerequisites pass. The
numbers express portfolio priority and convergence, not an all-to-all
dependency chain.

### Milestone 1: trustworthy frontend facts and request isolation

Outcome: stable lexical identities, exact source facts, complete dependency
observations, and no request-state leakage.

Owners: `haxe_ocaml-i7d5a`, `haxe_ocaml-850ii.32.2`,
`haxe_ocaml-850ii.32.4`, and the frontend numeric-literal owner.

Typed reuse, persistent caches, and concurrent semantic requests remain
deferred.

### Milestone 2: fail-closed standalone `reflaxe.ocaml`

Outcome: supported Haxe behavior has one validated owner before OCaml syntax,
and unsupported behavior stops with an actionable diagnostic.

Owners: `haxe_ocaml-9bome`, `haxe_ocaml-taef5`, `haxe_ocaml-w32h3`,
`haxe_ocaml-0uwin`, and `haxe_ocaml-s7jry`.

### Milestone 3: authentic native shared-target hard cut

Outcome: upstream Haxe and native `hxhx` feed the same standalone target
implementation. No Stage3 semantic emitter participates.

Owner: the hard-cut child of `haxe_ocaml-38gsp`.

### Milestone 4: Full1 closure by root semantic family

Outcome: one exact candidate opens the declared suite, target, macro/eval,
plugin, performance, provenance, and release evidence without stage0
delegation or generated-output repair.

This milestone does not add OCaml output or the shared-target hard cut to the
Full1 target matrix. The combined product aggregate depends on both outcomes;
the Full1 aggregate itself does not.

Owners: `haxe.ocaml-f1cl.3`, `haxe.ocaml-f1cl.3.1`,
`haxe.ocaml-f1cl.3.11`, and release owner `haxe.ocaml-f1cl`.

### Milestone 5: safe typed reuse and a defaultable native server

Outcome: repeated edits are materially faster while every warm result remains
equivalent to a clean process and retained memory stays bounded.

Owner: `haxe_ocaml-850ii.32` and its typed-reuse admission child.

This milestone may begin before Full1 closes when its direct identity,
dependency, lifecycle, differential, and memory gates are ready. It does not
then inherit or imply Full1 readiness.

### After the critical path

Resume M22, compiler-transform/customization products, broader binding/export
products, persistent caches, and repository extraction only when their
documented prerequisites are executable.

## Human Decisions Left Open

The review does not silently resolve these product questions:

1. `haxe_ocaml-ftrhr` still owns whether semantic version `1.0.0` is reserved
   for Full1 or a differently named scoped release. The current default
   recommendation remains Full1-only.
2. The first standalone `reflaxe.ocaml 1.0` must state its checked OCaml-library
   interop scope. Typed third-party ecosystem access remains a north star;
   whether one advanced workflow blocks the first 1.0 release requires an
   explicit product decision.
3. Stage3 may be retired after the hard cut or retained as a documented
   diagnostic/bootstrap lane. It cannot remain a competing supported semantic
   target.
4. Full1's declared target/generator scope remains unchanged unless the
   maintainer explicitly changes the public promise.

The existing maintainer direction already answers the QA-cadence question:
compiler-scale `hxhx` is a scheduled and critical-boundary target workload, not
an every-PR tax. Whether it becomes a standalone-target release blocker remains
claim-scoped.

## Evidence And Follow-Up Reviews

This review does not justify another whole-project Oracle checkpoint now.

Request a focused shared-target review at Milestone 3 with:

- the rewritten `haxe_ocaml-38gsp` contract and exact candidate;
- the native `hxhx` adapter into the standalone target;
- the pinned Reflaxe fork revision and neutral lifecycle evidence;
- one ordinary application and one bounded compiler-scale workload through
  both hosts;
- target, lowered-plan, runtime-reason, and output-manifest identities;
- OCaml compile/run results and phase/memory samples; and
- a guard showing that Stage3 semantic emission and generated-output repair did
  not participate.

Request a separate typed-reuse review only after the deterministic edit matrix,
seeded stress run, failure/reset evidence, and memory plateau data exist.

## Non-Claims

This checkpoint:

- does not implement the hard cut;
- does not make standalone `reflaxe.ocaml` 1.0-ready;
- does not make `hxhx` Full1-ready;
- does not enable typed-module reuse;
- does not ship M22 or customization;
- does not change the Full1 target scope;
- does not change README progress bars or percentages; and
- does not replace runtime, package, upstream-suite, or same-candidate CI
  evidence.
