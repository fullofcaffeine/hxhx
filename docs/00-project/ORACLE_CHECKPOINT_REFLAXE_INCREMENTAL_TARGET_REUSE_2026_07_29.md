# Oracle Checkpoint: Safe Incremental Reflaxe Target Reuse

Prepared: 2026-07-29

Status: focused architecture review accepted; observation and shadow replay are
the next implementation slice. No production target-cache hit, default server
support, release claim, or README readiness change is authorized by this
checkpoint.

Owning Bead: `haxe_ocaml-850ii.33.7`

Parent Bead: `haxe_ocaml-850ii.33`

Related native-server Bead: `haxe_ocaml-850ii.32`

Reviewed documentation candidate:
`d986d29022c827ddea571f0157b0c8fc98c57e9b`

Measured implementation candidate:
`097803880838ff640b3753196a26977d0ac78eac`

Review package SHA-256:
`e7f8ded3b9dd3f8f748bf1c4927cc553913bba60964be39203e742f958cbf2ce`

Controlling prompt SHA-256:
`90b32c23a1c33a25f70778ef310c2e7ab1c1d4e875316f012a327ad0d1213591`

## Outcome

The review selects a safe way to make an unchanged warm Reflaxe request avoid
repeating roughly 32 minutes of OCaml target generation.

On the first request, `reflaxe.ocaml` still performs its normal complete target
work and produces the full generated source tree. After that request succeeds,
the compiler may retain an immutable packed copy of those generated files plus
the facts needed to prove exactly what they represent.

On an identical later request, the compiler can eventually:

```text
build an exact current-program fingerprint
  -> find an entry with the same complete request identity
  -> replay all generated files into a fresh private directory
  -> rebuild and validate current ownership records
  -> replace the public source tree atomically
  -> run Dune normally
```

The first implementation slice does **not** skip target work. It builds the
identity and a second private replay tree, then compares that shadow tree with
the normally generated tree. A later child may enable exact hits only after
that comparison proves the key, payload, output transaction, diagnostics,
memory, reset, and failure behavior.

An **exact hit** means every source-generation input matches. The initial rung
does not reuse selected functions or modules after an edit. A private-body
edit, public signature change, define change, source move, macro change,
runtime change, target change, or uncertain observation causes a complete
miss. This coarse rule is deliberate: it delivers a large unchanged-request
opportunity without first inventing a serializable compiler IR or guessing
fine-grained invalidation.

## Soundness assessment

The recommendation is accepted for five reasons:

1. It addresses the measured bottleneck. The optimized cold and warm requests
   spent 1,936.617 and 1,915.754 seconds respectively in Haxe plus Reflaxe
   generation, while Dune already reduced its warm work to 1.035 seconds.
2. It keeps one semantic target compiler. A miss runs the existing
   `reflaxe.ocaml` pipeline; a hit replays bytes already produced and validated
   by that same pipeline.
3. It stores no mutable Haxe compiler graph. Current function plans retain
   request-owned typed expressions, types, variables, positions, and indexes
   keyed by host objects, so they are correctly rejected as cache payloads.
4. It preserves complete output replacement. Hits still use a fresh private
   output transaction, reconstruct current receipts and target claims, validate
   the whole inventory, and publish the complete tree.
5. It admits uncertainty as a miss. Macro-realm loss, unrevisioned callbacks,
   incomplete runtime authority, diagnostic/report modes, corruption, or an
   unknown ambient input cannot produce an optimistic hit.

The expected speedup remains an inference until measured. Replaying and hashing
the retained 27,792,458-byte tree should be much cheaper than rebuilding the
target for roughly 1,916 seconds, but key construction, evaluator allocation,
garbage collection, replay, manifest reconstruction, and publication must be
timed directly.

The proposed 128 MiB catalog budget and 64 MiB single-entry limit are accepted
as observation defaults, not permanent product constants. The implementation
must report packed bytes, index overhead, evaluator RSS, garbage collection,
eviction, and reset behavior before those values become shipping defaults.

## Provenance precision

The external reviewer reported that its active environment identified itself
as GPT-5.6 Pro rather than the requested GPT-5.6 Sol and did not claim that it
could change the already-active turn's effort setting. That disclosure is
preserved. The architectural decision is accepted because its cited source,
measurement, and lifecycle analysis is checkable, not because of an unsupported
model-provenance claim.

The review package verified 196 internal hashes, passed ZIP integrity, and
recorded zero Gitleaks findings. Candidate, pinned Reflaxe, and GPL upstream
Haxe 4.3.7 reference material remained segregated. Upstream sources informed
observable behavior and lifecycle analysis only; they do not authorize copying
or translating GPL compiler implementation into the MIT candidate.

## Hard boundaries

### What may survive

The first reusable entry is a complete generated source bundle containing:

- one explicit catalog and entry schema revision;
- one exact target-source request revision;
- compatible program and provenance revisions;
- packed immutable file bytes;
- a sorted index of normalized relative paths, byte ranges, hashes, owners,
  kinds, stability, profile eligibility, source identity, and provenance;
- the framework-owned path set needed to generate a fresh receipt;
- immutable target claims needed to generate a fresh artifact manifest;
- the expected source-bundle revision as a replay postcondition;
- a first-version diagnostic-eligibility marker; and
- exact payload and index accounting.

### What must never survive in the entry

The payload must not retain:

- `ClassFuncData`, `TypedExpr`, `Type`, `TVar`, or `Position`;
- current OCaml function plans or object-keyed occurrence maps;
- target compilers, compilation contexts, builders, printers, registries, or
  output writers;
- callback closures, macro globals, compiler contexts, or request-local lookup
  objects;
- open files, Dune `_build`, native binaries, native toolchain state, or the
  old public output directory; or
- a cached receipt or artifact-manifest file treated as current authority.

Receipts and manifests are rebuilt from the current request's validated
ownership facts. The old public directory is never a semantic cache input.

## Blocking corrections before production replay

### Complete source-bundle authority

`OcamlArtifactManifestBuilder` already exposes whether the target can account
for the complete source bundle. The current compiler seals semantic-runtime and
native-dependency authorities as incomplete. Therefore
`completeForSourceBundle == false` is a hard production-hit blocker.

The first slice may close authority conservatively by hashing the complete
packaged runtime source manifest and a normalized native-library/source-unit
declaration. It must not pretend that incomplete selective authority is
complete.

### Macro-realm lifetime

The process-local catalog may live only behind a narrow capability in the
upstream Haxe server's reusable macro-interpreter realm. Availability is an
optimization, not a semantic assumption: a cold or replaced realm is a miss.

A sentinel fixture must establish catalog identity and reset behavior across:

- successful request and exact repeat;
- macro source change;
- macro error;
- `NoMacroCache`;
- classpath or compiler-signature change;
- explicit reset; and
- server restart.

If this lifetime cannot be proven, this design stops. Disk persistence is not a
fallback inside this Bead.

### Source-position cache hygiene

`OcamlSourcePositionMapper` currently caches source contents and line starts by
path for the life of the macro process. Editing line structure at the same path
can therefore leave source-map positions stale during a warm request.

Before reuse, that state must be reset per request or keyed by a complete
content revision. A clean-versus-warm source-map fixture must insert and remove
newlines before a mapped expression and compare generated positions.

### Eligibility and diagnostics

The initial hit path is ineligible when:

- an unrevisioned target or plugin callback is registered;
- progress, telemetry, lowering-report, lifecycle-trace, or another skipped
  plan-evidence mode is enabled;
- the matching miss emitted a target-generation warning or error that would
  need replay;
- a source-affecting define, resource, environment input, runtime input,
  source-position input, or implementation identity is not represented; or
- source-bundle authority is incomplete.

Frontend and Dune diagnostics still run fresh. Stable target diagnostic replay
is deferred until it can reconnect immutable diagnostic data to fresh
request-local positions.

## Identity model

The exact lookup key uses schema-tagged, length-delimited canonical data and
SHA-256. Maps sort by normalized key, while program facts whose order affects
output preserve that order.

The final request identity must account for:

- stable declaration, source-origin, final-body, public-API, implementation,
  module, and ordered program-membership revisions;
- Haxe build, ordered classpaths and libraries, defines, DCE/features, compiler
  options, generated declarations, resources, and selected source origins;
- Reflaxe implementation, lifecycle, filter, preprocessor, and callback
  revisions;
- `reflaxe.ocaml` implementation, target configuration, runtime inputs, output
  grouping, printer, receipt, manifest, and codec schema revisions; and
- every declared source-affecting ambient input.

The current `ProgramRevision` remains useful compatibility evidence but is not
a complete lookup key. It globally sorts entries and does not by itself own
source origin, declaration order, complete configuration, macros, resources,
runtime inputs, output schema, or diagnostics eligibility.

The richer `FinalProgramFingerprintSnapshot` should derive the existing
`ProgramRevision` where practical so key construction does not repeat a full
typed-body walk. If key construction needs the dominant target preparation or
approaches target-generation cost, implementation must stop and redesign.

## Probe and request lifecycle

The current OCaml `filterTypes` path performs
`precomputeWholeProgramContext(...)` before the current `ProgramRevision`
exists. Probing after that call would preserve a large part of the measured
cost.

The target lifecycle must therefore separate:

1. cheap final type selection and strict validation required on hits;
2. target-neutral final-program fingerprinting and eligibility;
3. exact catalog lookup and payload validation; and
4. miss-only OCaml preparation, registries, preprocessors, planners, syntax,
   runtime inference, reports, and artifact generation.

A validated hit obtains a read lease, opens a fresh private transaction,
replays all stable files and claims, regenerates the framework receipt and
target manifest, validates every path and digest, publishes the complete tree,
runs Dune normally, and releases the lease in `finally`.

A miss runs the existing target pipeline. It may construct an immutable
candidate only after the private source tree and all authorities pass. The
candidate becomes visible to future requests only after source publication and,
when requested by that invocation, successful Dune completion.

Filesystem publication, Dune, and catalog admission are separate ordered
commits:

```text
publish complete generated source
  -> run optional Dune build
  -> admit a newly produced immutable entry
```

A Dune failure follows the existing contract: already-published source remains
public, no new entry is admitted, and an older independently validated source
entry is not corrupted.

## Memory and corruption

The observation rung starts with:

- a 128 MiB hard packed-payload budget;
- a 64 MiB maximum single entry;
- immutable entries;
- read leases that pin active entries;
- weighted LRU eviction among unleased entries;
- explicit all/namespace reset;
- no-admission rather than budget overflow;
- quarantine on schema, key, path, inventory, or hash failure; and
- redacted deterministic statistics.

Reports include entries, bytes, estimated overhead, RSS/GC delta, hits, misses
by reason, ineligible requests, admissions, rejected admissions, evictions,
quarantines, leases, key time, lookup time, replay time, manifest time, skipped
target work, and reset cause. They must not expose source text, raw define or
environment values, or machine-local paths.

Thirty exact requests and multi-entry churn must approach an RSS plateau.
Reset must reduce catalog entry count and payload bytes to zero. The final ten
requests may grow by no more than 32 MiB, and catalog-attributable retained
growth must remain within configured payload plus measured bounded overhead.

## Implementation sequence

### Child 1: exact identity and shadow replay

The immediate child under `haxe_ocaml-850ii.33.7` is:

> Prove exact target request identity and shadow source-bundle replay

It adds the immutable final-program fingerprint, exact target request key,
eligibility result, macro-realm sentinel, authority closure, packed replay
candidate, source-position correction, bounded catalog mechanics, and a shadow
replay into a second private directory.

Normal target output remains the only publication source. No semantic work is
skipped. The shadow must match normal output in paths, bytes, hashes, receipt
semantics, target claims, artifact manifest, source-bundle revision,
diagnostics, executable, and behavior.

### Child 2: bounded exact hits

Create the following child only after Child 1 passes:

> Enable bounded in-memory exact target source-bundle hits

It enables opt-in exact hits for eligible unchanged requests. Every edited or
uncertain request remains a miss. Temporary observe/shadow migration flags must
have explicit removal gates; the end state retains one miss compiler and one
operational enable/disable control, not two semantic pipelines.

### Later edited-request reuse

Fine-grained function or module reuse remains deferred. It requires a new
detached plain-data capsule, stable source and occurrence identities, exact
consumed dependency revisions, whole-program/SCC facts, and evidence that
enough work survives real edits to justify the additional semantic boundary.

No current OCaml function-plan object becomes that capsule.

## Correctness and performance gates

The existing clean/warm matrix must be extended rather than replaced. It covers
exact repeat, private and public edits, add/delete/move, classpath shadowing,
defines/profiles/DCE, build-macro edit/restore, malformed input, A→B→A,
pre-publication failure, repeated-request memory, restart, and package use.

Add macro realm/error/`NoMacroCache`, runtime/support changes, source-map newline
edits, resources, callbacks, report/diagnostic modes, corruption, reset,
eviction, Dune failure, cancellation, crash points, namespace isolation, and
budget churn.

Every qualified comparison covers diagnostics and positions, complete file
inventory and bytes, request/program/bundle revisions, fresh receipt, fresh
artifact manifest and authorities, stale-file deletion, Dune ownership,
executable digest on a fixed environment, and runtime exit/stdout/stderr.

The existing product gate remains:

- save at least 120,000 ms in the complete warm loop; **or**
- reach a warm/cold complete-loop ratio no greater than `0.80`.

The reuse mechanism must additionally:

- execute zero miss-only target preparation, lowering, or syntax on a hit;
- reduce hit target-generation time to at most 20% of cold target generation;
- pass at least three independent compiler-scale exact-hit sequences;
- preserve complete byte and behavior equivalence; and
- remain within the memory and authority gates above.

## Native self-promotion priority

Target replay and native Reflaxe promotion are complementary:

- replay accelerates the current upstream-Haxe server route; and
- native promotion runs the Haxe-authored target core as native code.

The project should pursue both, but they must converge on one semantic
implementation. After `haxe_ocaml-38gsp.1` proves that native `hxhx` invokes the
actual standalone target core, a bounded successor must compile that same
Haxe-authored `reflaxe.ocaml` core through `reflaxe.ocaml` into a native
`hxhx` plugin or builtin artifact and compare it with evaluated execution.

Older “self-host plugin” receipts proved that upstream Haxe or strict `hxhx`
could generate and load an OCaml plugin containing a backend provider. Their
current fixture packages `backend.js.JsBackend` through the independent Stage3
route. That is valuable loader and ABI evidence, but it is not proof that the
standalone `reflaxe.ocaml` semantic target compiled and executed itself.

The near-term self-promotion proof is narrower than the deferred M22 product:
it does not promise one stock-Haxe/`hxhx` ABI, a public SDK, package
installation, upgrade/rollback, or a supported shared payload. Those remain
M22 work after Full1 and the authentic target hard cut. The bounded proof must
still use the real standalone target, retain one semantic core, record artifact
and implementation identities, and measure build, load, target execution,
output equivalence, memory, and end-to-end latency.

### Typed OCaml access for native Haxe-authored tools

Self-promotion should let the native target use the OCaml platform without
turning its Haxe source into raw target-language fragments. The ownership model
has two separate typed boundaries:

1. `reflaxe.ocaml` owns Haxe-facing OCaml platform libraries: exact externs for
   representable OCaml APIs, generated typed bindings for suitable `.mli`
   interfaces, and small checked `.ml`/`.mli` adapters for OCaml features Haxe
   cannot express faithfully.
2. A compiler host owns versioned compiler facts and services. It exposes
   immutable program snapshots and capability-limited actions, not its private
   mutable OCaml compiler graph.

Native `hxhx` and a self-promoted `reflaxe.ocaml` may both consume the first
layer. The native target may consume the second only through the same declared
host capability contract as any promoted target.

This does not mean importing every private upstream Haxe compiler module as a
public Haxe library. Platform APIs and appropriate `compiler-libs` surfaces may
be represented exactly or wrapped by a checked adapter. Private host state
remains behind the plugin boundary. Unsupported OCaml types fail with a
specific binding/adapter diagnostic instead of widening to `Dynamic`, `Obj.t`,
or an unexplained `Obj.magic`.

`haxe_ocaml-v8a9b` remains the one product owner for typed OCaml imports,
adapters, native dependencies, toolchain locks, ownership, and provenance. The
self-promotion proof may use the already declared typed low-level facade and
one narrowly accepted adapter; it must not create a competing interop system or
wait for every future ecosystem binding before measuring native target
execution.

## Stop conditions and non-claims

Stop and redesign if:

- one exact key produces different output, claims, diagnostics, executable, or
  behavior;
- a payload can reach mutable compiler or target objects;
- source-bundle authority cannot close before dominant target work;
- the macro realm cannot reliably own and reset the bounded catalog;
- source, configuration, macro, runtime, callback, or output changes can hit a
  stale entry;
- positions or target diagnostics cannot remain exact;
- corruption cannot be quarantined before publication;
- memory cannot be accounted, capped, evicted, reset, and shown to plateau;
- implementation creates a second target compiler;
- exact hits still fail both product performance gates; or
- scope expands to persistence, concurrent semantic requests, macro-result
  caching, plugin-state reuse, or source-plus-Dune atomic rollback.

Keep `haxe_ocaml-850ii.33.7`, `haxe_ocaml-850ii.33`, and
`haxe_ocaml-850ii.32` open in their separate roles. The exact-bundle rung can
close the unchanged-request performance child only after evidence; it does not
complete edited-request reuse or the native `hxhx` server.

README Goals bars and default server support remain unchanged. This checkpoint
selects an implementation boundary and prioritizes authentic native
self-promotion; it does not implement either capability.
