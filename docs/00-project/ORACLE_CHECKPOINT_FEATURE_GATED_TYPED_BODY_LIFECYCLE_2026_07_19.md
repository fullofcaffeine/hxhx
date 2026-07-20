# Oracle Checkpoint: Feature-Gated Typed-Body Lifecycle

Prepared: 2026-07-19

Status: GPT-5.6 Pro diagnosis accepted for the marker-loss defect; host-specific
trigger remains open; implementation is owned by `haxe_ocaml-7201t`

Owning Bead: `haxe_ocaml-7201t`

Related Beads: `haxe_ocaml-850ii.22`, `haxe_ocaml-850ii.21`, and
`haxe_ocaml-s7jry.4`

Decision trail:
[`FEATURE_GATED_TYPED_BODY_LIFECYCLE_DECISIONS.tsv`](FEATURE_GATED_TYPED_BODY_LIFECYCLE_DECISIONS.tsv)

## Outcome

The immediate failure has a concrete source-level cause:

1. `PreservePlaceAssignmentsImpl` wraps an admitted assignment or update in
   target-owned `:reflaxeOcamlPlaceOrigin` metadata.
2. The wrapper protects the operation from Reflaxe's
   Everything-Is-An-Expression rewrite, which could otherwise change the
   evaluation schedule of an effectful place.
3. Reflaxe's final `RemovePureExpressions` pass treats `TMeta` as transparent
   when it processes a standalone block element. It keeps the inner assignment
   or increment/decrement but discards the target-owned wrapper.
4. `OcamlBuilder` receives the still-admitted update without its origin and
   correctly stops at `ocaml-lowering:place-invariant`.

This is a Reflaxe preprocessing lifecycle defect. It is not evidence that Haxe
inserts the update after the OCaml preservation pass.

The hosted-macOS-only exposure is a separate, still-open trigger question. The
passing Linux and local-macOS routes do not disprove the generic marker-loss
path; they show only that those routes did not expose the same final operation
in the same way. Closure still requires exact toolchain, option, retained-type,
feature, and final-body comparison.

No README or North Star readiness bar changes because this checkpoint corrects
the diagnosis and architecture plan; it does not repair or validate the
package route.

## Review Provenance

The response identifies these reviewed inputs:

- candidate: `f9b6f879dd4b65a25e374433bfa0cdea5a7fba82`;
- Reflaxe framework: `73a983112e039daad46b37912ab238df6bf0cf53`;
- upstream Haxe 4.3.7:
  `e0b355c6be312c1b17382603f018cf52522ec651`;
- source package SHA-256:
  `b95e618140e26ad1c1a5163bedd104e84e9176c525fffba249d57ca97e7e109d`;
- reviewed archive SHA-256:
  `d8bf8acf87dccfd9a69a71be03776181198251d3e77a2eb4b6948ce6a39fa5a3`.

The last item is important: the response reviewed the original R1 archive,
even though the Bead later marked that archive superseded by R2:

`339b52fdeb83edd8a9a74ea1d4ebb20fbeeeac992370493768061f24d88017f0`.

R2 retains the same candidate and reference commits but adds the bounded Haxe
server-delta experiment and exact Reflaxe output-manager source. Therefore:

- the marker-loss diagnosis and static lifecycle finding are independently
  reviewable and were also rechecked directly in the local committed sources;
- claims that depend on R2-only server evidence are local evidence, not part of
  this Oracle's independently verified review basis;
- a later review of a concrete Reflaxe lifecycle PR is the preferred second
  checkpoint for the server/cache contract if one is needed.

The Oracle also found a packaging defect in R1: its manifest said the nested
exact source ZIP and producer manifest were present, but they were absent from
the archive and checksum list. Future review bundles must either include those
payloads or stop claiming they are included.

## Independently Verified Source Facts

The local source at the reviewed identities confirms all facts needed for the
immediate diagnosis:

- Haxe calls `Finalization.generate`, runs its filter pipeline, and only then
  invokes after-generation callbacks.
- Haxe DCE is followed by exception-constructor patching, field-initializer
  movement, feature commit, and the remaining post-DCE type filters.
- Reflaxe registers both `onAfterTyping` and `onAfterGenerate`, but starts target
  compilation from its `onAfterGenerate` callback.
- Reflaxe overwrites, rather than accumulates, its stored `onAfterTyping` batch.
  Haxe may invoke that callback repeatedly with newly discovered types, so this
  is an independent framework lifecycle defect.
- `findFuncData` reads the current post-filter `field.expr()` and stores a
  mutable `ClassFuncData` in a process-global, unrevisioned cache.
- `PreservePlaceAssignmentsImpl` runs before the Reflaxe default preprocessors.
- Everything-Is-An-Expression preserves a `TMeta` envelope while processing its
  child.
- `RemovePureExpressions` keeps bare assignments and updates, but replaces a
  `TMeta(_, child)` block element with `child` for further processing.
- `OcamlBuilder` recognizes only the retained target origin and otherwise
  recursively strips ordinary metadata.

These facts correct earlier source and Bead comments that described Haxe as
materializing or inlining the failing expression after Reflaxe preprocessing.

## Accepted Architecture

The accepted direction is a bounded combination of B, C, and D from the review.

### B: one OCaml-owned preprocessing lifecycle

The place family needs one ordered owner:

```text
final copied host body
  -> early protection before generic value rewrites
  -> declared generic structural rewrites
  -> final admission and immutable place planning
  -> seal and validate
  -> mechanical OCaml syntax construction
```

Early protection and final planning have different jobs. Early protection keeps
generic rewriting from changing observable place semantics. Final planning
binds origins and plans to the exact body that reaches syntax construction.
Blindly rerunning the current origin pass is not an acceptable substitute.

No expression preprocessor may run after the final seal unless it explicitly
invalidates and rebuilds every affected plan.

### C: explicit program and body revisions

An identity answers *which function or operation is this?* A revision answers
*does this plan still describe the body being emitted?* They must remain
separate.

At minimum, a sealed plan is keyed by:

- stable function identity;
- normalized program revision;
- exact final working-body revision;
- target pipeline/schema revision;
- deterministic structural operation identity.

Source positions remain diagnostic evidence. They are not semantic keys.
Host object identity, memory addresses, absolute paths, mutable compiler
objects, and unversioned `Std.string(Type)` output are not durable identities.

Request-local working data is the default. A persistent compiler-server cache
may reuse only immutable artifacts under exact revision keys. Mutable
`ClassFuncData` must not cross program revisions.

### D: narrow Reflaxe lifecycle contract

The durable framework seam is intentionally small and target-neutral:

- a request-local immutable function input carrying a stable function ID and
  host-body revision;
- a named opaque semantic envelope or analysis family owned by the target;
- a declared per-preprocessor action: preserve, consume/replace, invalidate, or
  reject;
- framework verification of the declared action;
- a final validation boundary before target compilation;
- revision-scoped cache behavior and complete reconciliation of repeated
  `onAfterTyping` batches.

This is not authority for a universal Reflaxe IR, a broad pass manager, a
cross-target semantic model, or OCaml-specific logic in Reflaxe.

Any Reflaxe implementation must be prepared in a separate clean worktree and
landed through its own repository pull request. Its commit and pull-request body
must state that it is an `hxhx-agent` change prompted by this typed-body
lifecycle incident and link the target-side evidence. The shared reference
checkout must remain untouched.

## Qualified Findings

### `onAfterGenerate` is the current host boundary, not an eternal guarantee

For Haxe 4.3.7's reviewed route, Reflaxe starts after Haxe's built-in DCE and
filter work. The target must copy, normalize, and seal its inputs immediately
when its callback runs. It must not call mutable macro objects an immutable
snapshot merely because they were observed in `onAfterGenerate`.

Callback registration/order should be traced once. If another callback mutates
selected bodies after the proposed seal but before they are emitted, stop and
move or redesign the boundary. Later mutations after Reflaxe has completed its
output are not part of that already-finished target invocation.

### The direct defect does not explain the host trigger

The source proves how a marked standalone update loses its owner. It does not
prove why the hosted macOS route selects or retains the failing shape while the
other two routes pass. Required comparison includes exact Haxe executable and
stdlib identity, Reflaxe content identity, normalized arguments and defines,
DCE mode, retained declarations, relevant feature state, and canonical initial
body digest.

### Source-shape workarounds are provisional

Removing `inline` from the exception stack helpers and omitting the explicit
zero initializer moved the failure and kept behavior green on tested routes,
but neither change fixes marker loss. After the lifecycle fix, restore and test
each source shape independently. Retain a changed shape only for a separately
documented semantic, generated-code, or performance reason.

## Rejected Shortcuts

- Do not hand-tag `Exception.hx` or any user/source expression with target
  metadata.
- Do not keep rewriting feature-gated stdlib expressions until CI happens to
  pass.
- Do not disable DCE, feature gating, or exception stack behavior.
- Do not make every preprocessor preserve every metadata item blindly.
- Do not move preservation to the end as the only fix; earlier value rewriting
  may already have changed evaluation behavior.
- Do not rebind or plan the source operation in `OcamlBuilder`.
- Do not recover through raw OCaml, `Dynamic`, `Obj.magic`, unit/null
  placeholders, or the legacy assignment path.
- Do not use source offsets or object identity as semantic IDs.
- Do not keep old and new semantic paths behind a production switch.
- Do not introduce a broad shared IR or CFG for this bounded lifecycle defect.

## Migration And Proof Order

1. Correct the lifecycle record in source comments and Beads.
2. Add a direct unit proving what `RemovePureExpressions` does to a marked
   standalone update, plus a per-pass test locating the first loss boundary.
3. Add a small feature-gated fixture independent of `haxe.Exception` and an
   output-inert, bounded lifecycle trace.
4. Land the narrow Reflaxe contract in its own worktree and repository PR, with
   independent framework tests and the required `hxhx-agent` signature.
5. Hard-cut the OCaml place family to early protection, final revision-bound
   planning, sealing, and one mechanical syntax path.
6. Prove local arm64 macOS, hosted arm64 macOS, and hosted Linux against the
   same verified package and exact toolchain/framework identities. Include
   fresh and revisioned server routes without mixing their output ownership.
7. Re-evaluate the two temporary `Exception.hx` source-shape changes one at a
   time.
8. Close the correctness Beads before resuming report-only cross-host latency
   measurement.

The ordinary edit loop uses the direct Reflaxe and focused target tests. It must
not rebuild all of `hxhx`, regenerate broad bootstrap snapshots, or run every
backend merely to diagnose this target lifecycle seam.

## Closure Conditions

The lifecycle blocker closes only when all of these are true:

- the direct marker-loss and full-order regressions pass;
- early protection survives every pass that could change place semantics;
- final plans describe the exact sealed body revision;
- stale, missing, or undeclared ownership fails before OCaml emission;
- repeated `onAfterTyping` batches and compiler-server revisions cannot reuse
  incomplete or mutable stale input;
- the feature-gated and exception fixtures match Haxe 4.3.7 behavior;
- one exact package passes hosted Linux, hosted arm64 macOS, and local arm64
  macOS with bounded deterministic evidence;
- future evidence bundles accurately list and include their payloads;
- no builder fallback, source hand-tag, DCE weakening, raw fragment, or broad
  architecture expansion was introduced;
- README Goals and North Star remain unchanged unless separate user-visible
  production evidence justifies a later update.
