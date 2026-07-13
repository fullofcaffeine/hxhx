# GPT-5.6 Pro Review Integration — 2026-07-12

This checkpoint records how the external whole-repository review was
reconciled against current `main`, live GitHub evidence, repository contracts,
and the authoritative beads database. The external report is advisory; this
document records the repo-owned decisions.

## Verdict

Accepted overall: **sound with corrections**. The product vision, clean-room
boundary, frontend/backend ownership, target-core/ABI direction, and bounded
Cpp evidence model remain coherent. The active release program needed
correction: current required reds were unowned, several active epics accepted
gate construction rather than achieved outcomes, product rows pointed to
closed foundations, target scope was underspecified for an unqualified
drop-in claim, and the Full1 RC could refuse unsupported publication but could
not positively authorize a candidate with complete provenance.

This is a plan correction, not a compiler rewrite.

## Current evidence reconciliation

The review's highest-impact claims reproduced at `b094f7bb`:

- Core PR run `29209024798` failed because the Cpp plan retained a
  machine-local absolute path. Owner: `haxe_ocaml-t7bmv`.
- Portable Tier1 run `29209024773` failed while compiling the Rest fixture
  because upstream Haxe reported no `toString` member on the native Rest
  representation. Owner: `haxe_ocaml-lg7be`.
- after the local-path correction, the full Core guard bundle exposed the next
  masked frontier: `CppTargetCore` used a broad `Dynamic` catch in its timing
  buffer. Owner: `haxe_ocaml-r0j8c`. Typed exception/string rethrow coverage
  and the full local guard bundle now pass; remote evidence is still required.
- the RC workflow synthesized detailed suite/target/macro/plugin markers from
  aggregate job results;
- the RC v1 summary lacked candidate and child-artifact provenance;
- the automatic RC release event was post-publication;
- semantic release did not download or validate an RC artifact.

Other push lanes at the same commit included successful Gate1 Lite, Gate2 Lite,
Gate3 builtin/native smoke, JS oracle smoke, semantic-diff, report-only KPI,
and security runs. Those successes remain useful evidence for their declared
scope; they do not cancel the two required reds or prove Full1.

### Phase 0 follow-up

The required baseline is now restored at
`4997112334e808547d20e843eb8f978378b50911`: Portable Tier1 run
`29225866229` and Core PR run `29225866252` both passed on attempt 1. The
machine-local path, typed Cpp timing-buffer catch, OCaml Array/Rest string
surface, generated snapshot, and linked-JS class-order frontiers each have
focused repo-owned coverage and closed evidence beads.

`haxe_ocaml-145dn` then turned the review's ownership rule into an executable
loop. `docs/00-project/CI_EVIDENCE_OWNERSHIP.json` names watched workflows and
incidents; the evaluator joins live GitHub runs to active Beads; and
`CI / Evidence Ownership Audit` reports unowned, cancelled-without-successor,
stale, or missing evidence. The current scheduled macro, M7, Full1, and
manual-KPI gaps remain explicitly open. This is accountability evidence,
not Full1 or product-readiness progress, so the README/North Star state is
unchanged.

### Plugin evidence follow-up

The review's warning about job-status-derived plugin evidence is now resolved
under `haxe_ocaml-gskz9` and child `haxe_ocaml-gskz9.1`. Run `29281925684` at
candidate `31eaa7e583dc6b0217438fe745003a775a526d2d` passed all three real
plugin routes. Its aggregate downloaded the exact same-run artifacts, checked
the candidate/host/stage0/load/runtime fields, re-hashed each uploaded plugin
file, and emitted `FULL1_PLUGIN_PARITY:PASS` from a zero-error
`full1-plugin-parity-summary.v3` receipt. The Full1 RC collector now rejects
the older result-only v2 shape.

This closes the Full1 plugin workload outcome, not the broader supported
plugin product. Package/install, public support/versioning, repeated target
workloads, and release-grade product artifacts remain under
`haxe_ocaml-bomhr`. The README bar therefore stays unchanged.

## Accepted and integrated

1. **Outcome-based Full1 ownership.** `haxe.ocaml-f1cl`, `.3`, `.3.1`, and
   `.3.11` now own same-candidate outcomes rather than workflow/marker
   existence. Target-specific implementation stays in bounded children.
2. **Required-red and scheduled-evidence ownership.** `haxe_ocaml-145dn` owns
   the durable classification, freshness, cancellation, and closure loop.
3. **Explicit Full1 outcome lanes.** Macro/eval `haxe_ocaml-vhk47` and
   performance `haxe_ocaml-u6esu` remain active successors to completed
   contract/workflow foundations. Plugin outcome `haxe_ocaml-gskz9` is now a
   completed same-candidate workload foundation as recorded above.
4. **Target-scope decision.** Completed under `haxe_ocaml-rttuj`. C++/Cppia,
   both HashLink forms, JS, Lua, Neko, PHP, C#, Java source, Python, and native
   interpreter/run behavior are required. Flash/SWF is intentionally
   incompatible; direct JVM bytecode and XML/JSON type descriptions are
   deferred. The guarded plain-language table is
   `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`.
5. **Scoped version identity.** `haxe_ocaml-ftrhr` owns the xhigh choice. The
   current safe default is a Scoped profile candidate under `0.x`, because
   current enforcement reserves semantic versions `>=1.0.0` for Full1.
6. **Prepublication provenance.** Completed foundation `haxe_ocaml-7c1ke` owns authentic child
   artifacts, candidate SHA/version, manifest digests, run attempts, artifact
   IDs/digests, timestamps, evidence tier/freshness, release handoff, and
   negative fixtures.
7. **Successors, not reopened history.** Closed bounded foundations remain
   closed. Active product successors are standalone `reflaxe.ocaml`
   `haxe_ocaml-s7jry`, combined `hxhx + reflaxe.ocaml` `haxe_ocaml-38gsp`,
   promotion product `haxe_ocaml-bomhr`, latency loop `haxe_ocaml-850ii`, and
   post-Full1 customization/variation lifecycle `haxe_ocaml-h5jta`.
8. **Evidence hierarchy.** Policy/schema fixtures, focused regressions,
   snapshots, runtime/native smokes, upstream suites, authentic workloads,
   measured performance, and release aggregates are distinct levels. Lower
   levels do not enter a higher-level product claim as substitutes.
9. **Bounded architecture work.** Bridge exit/non-expansion criteria are owned
   by `haxe_ocaml-slobw`; giant smoke decomposition by `haxe_ocaml-o2udb`.
   General GenIR/frontend-framework rewrites remain quarantined research.

## Adjusted recommendations

- README bars remain as coarse editorial indicators because repository policy
  still requires them, but numeric percentages were removed. Declared state,
  strongest evidence, freshness, owner, and next blocker control the claim.
- Cpp burn-down is not stopped. C++ and Cppia are mandatory for the first
  Full1 claim, so their matrix outcome is P1. `haxe_ocaml-94hk1` remains a
  valid P2 bounded attribution leaf until current profiling proves that its
  specific seam has critical-path leverage.
- The review recommended several plausible extractions. Only bridge ownership
  and smoke decomposition received immediate beads. Cpp/source/emitter
  extraction remains trigger-based because existing closed extraction work
  already established boundaries and no fresh profile justified another broad
  refactor.
- The standalone target is not demoted to research. It is an advanced preview
  and a production candidate only for its declared matrix after app validation;
  `haxe_ocaml-s7jry` owns the broader release-grade product claim.

## Rejected non-actions

- no blanket reopening of `haxe.ocaml-ro10`, `haxe.ocaml-n5ae`,
  `haxe.ocaml-rpmx`, `haxe.ocaml-vary`, `haxe.ocaml-5rjl`, or
  `haxe.ocaml-anoy`;
- no weakening of strict upstream-suite, no-stage0, no-skip, macro, plugin, or
  performance requirements;
- no copied, translated, mechanically rewritten, or vendored upstream Haxe
  compiler/test material;
- no compiler-wide neutral IR or Reflaxe-owned frontend redesign;
- no inference of detailed release evidence from aggregate job status;
- no public semantic `1.0.0` authorization from the current RC v1 path.

## Corrected critical path

1. Restore and own current-head required truth:
   `haxe_ocaml-t7bmv`, `haxe_ocaml-r0j8c`, `haxe_ocaml-lg7be`,
   `haxe_ocaml-145dn`.
2. Resolve claim boundaries:
   `haxe_ocaml-rttuj`, `haxe_ocaml-ftrhr`.
3. Produce authentic same-candidate suite, target, macro/eval, plugin, and
   performance evidence:
   `haxe.ocaml-f1cl.3`, `.3.1`, `.3.11`, `haxe_ocaml-vhk47`,
   `haxe_ocaml-gskz9`, `haxe_ocaml-u6esu`.
4. Build and validate the prepublication RC/release chain:
   `haxe_ocaml-7c1ke`.
5. Close the Full1 candidate epic only after release consumes that exact
   evidence: `haxe.ocaml-f1cl`.

Standalone `reflaxe.ocaml`, telemetry, and low-risk hackability work may run in
parallel. The combined native product and promotion support claims depend on
their relevant Full1 evidence. Customization platform expansion remains
post-Full1 by default.

## Readiness decision

No progress bar increased. This checkpoint corrected wording and ownership but
did not add new compiler/runtime/product evidence. Readiness cannot advance
while current required lanes are red or while the positive Full1 release path
lacks candidate-bound provenance.
