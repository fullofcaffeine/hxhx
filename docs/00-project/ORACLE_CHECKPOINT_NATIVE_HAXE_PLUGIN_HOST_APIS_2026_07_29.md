# Oracle Checkpoint: Native Haxe Plugin Host APIs

Prepared: 2026-07-29

Status: focused architecture and provenance review accepted with required
redesign. This checkpoint changes future M22 planning only. It does not
implement a shared SDK, authorize a native plugin package, or change Full1.
The README ranges were recalibrated in the same maintenance slice from existing
executable evidence; the review itself adds no readiness.

Owning checkpoint Bead: `haxe_ocaml-c4czv.1`

Parent M22 ABI Bead: `haxe_ocaml-c4czv`

Reviewed candidate:
`981c75d310287f1496fc484adba42b79172184fe`

Review archive SHA-256:
`309db5c4e3c5a98b9919eba0630fc5ac92bfbe9da5dbacadcf17b1c196285eb5`

Controlling prompt SHA-256:
`6f4cd7536476fa79358a2c75e69524a6774865344f1f2528e6fdb203c3ea8c1b`

Review runtime reported by the reviewer: GPT-5.6 Pro. The review did not claim
GPT-5.6 Sol or a user-visible `thinking:max` runtime switch.

## Outcome

The project should still let a developer write one target in Haxe, run it
through normal Reflaxe while developing it, compile the same implementation to
native OCaml, and host it from stock Haxe or `hxhx`.

The corrected product invariant is:

```text
one Haxe target implementation
  -> one versioned semantic request/result contract
  -> small host adapters for activation and transport
  -> equivalent target output and behavior on every supported host
```

A **semantic contract** says which immutable program facts the target receives,
which bounded host actions it may request, and how success, failure,
cancellation, diagnostics, and output publication behave. It is the part that
must remain identical across hosts.

A native `.cmxs` file is only one possible container for that implementation.
Stock Haxe and `hxhx` can link different OCaml compilation units, runtime
versions, and loader modules. Requiring one byte-identical container could
therefore force host-private details into the target core. M22 must test a
single-container build, but it may use tiny generated host-specific shells by
default when both shells invoke the same semantic core and contract.

The review also corrects the ownership model. There are three compiler-host
layers and one separate native-language layer:

1. a portable target contract owned by generic Reflaxe;
2. exact, version-pinned stock-Haxe host profiles;
3. an `hxhx` implementation of the compatible baseline plus negotiated
   extensions; and
4. an orthogonal typed OCaml interoperability layer owned by
   `reflaxe.ocaml`.

The fourth layer is not another compiler-host API. It lets Haxe-authored native
code call ordinary OCaml libraries through exact bindings or checked adapters.
It does not grant access to compiler state.

## Soundness assessment

The review is accepted because it corrects five high-consequence ambiguities.

### One core matters more than one container

OCaml native plugins are coupled to compiled interface digests, linked modules,
runtime identity, architecture, and loader behavior. Two small shells can
legitimately differ while the target's source, semantic core, request schema,
and observable output remain the same. Packaging identity is useful evidence,
but it is not the definition of semantic convergence.

### Native execution is separate from compiler privilege

Compiling Haxe target code to native OCaml lets that code call linked OCaml
libraries. It does not automatically reveal the current compiler's parser,
typer, macro state, reachability graph, diagnostics, or output transaction.
Those are host-owned facts and actions. A supported host passes immutable
snapshots or exposes a small capability-limited service.

### Stock Haxe has a real native plugin seam, but not dynamic target registration

Haxe 4.3.7 exposes `eval.vm.Context.loadPlugin` for exact-version eval plugins.
Its official example uses eval value conversion, registration, the current
macro/compiler API, and an after-typing callback. Stock custom targets still
activate through the public Haxe macro and Reflaxe lifecycle. The project must
say “public Reflaxe target with an exact native eval helper,” not “register a
new stock-Haxe platform dynamically.”

### Useful parity is a deliberate profile

A handwritten OCaml plugin can technically import unsafe or private compiler
modules. The project should not promise every reachable symbol. It should
define named supported profiles and prove that a Haxe-authored native plugin
has the same observable behavior as a small handwritten OCaml reference for
every admitted capability.

Each inspected capability receives one disposition:

- exact typed binding;
- checked `.ml`/`.mli` adapter;
- versioned host fact or service;
- isolated helper-process operation;
- research-only exact-host access; or
- rejected unsupported/private access.

Unsupported interfaces must fail. They must not silently widen to `Dynamic`,
`Obj.t`, or an unexplained `Obj.magic`.

### Exact stock profiles are versioned products, not a universal compiler API

Haxe's native eval API explicitly depends on matching Haxe and OCaml versions.
Haxe 4.3.7 and a future final Haxe 5 therefore need separately generated,
separately named, independently tested profiles. The current Haxe 5 development
snapshot is useful for extractor and compatibility-diff research only; it is
not final Haxe 5.0.0 support.

## Limits of this decision

The review was a static source and evidence audit. It did not execute the
cross-load experiment, build the exact stock adapter, prove the four host
lanes, or measure boundary overhead. The one-container conclusion is therefore
an architecture decision with a required experiment, not an empirical claim
that one container will fail.

The licensing section is engineering risk classification, not legal advice.
Any distribution that derives declarations from private GPL compiler
interfaces, links or bundles GPL compiler units, or claims an MIT-only combined
artifact needs an explicit distribution decision and qualified legal review.

The proposed public API remains provisional until the authentic standalone
target hard cut and bounded two-generation native self-promotion produce real
consumer evidence. M22 must not freeze a broad schema around the current
Stage3 emitter or speculative compiler services.

## Durable ownership model

| Boundary | Owner | Positive contract | Excluded authority |
| --- | --- | --- | --- |
| Portable target API | generic Reflaxe | Versioned immutable target request, program/facts snapshot, requirement vocabulary, bounded service catalog, result, diagnostics, output/build plan, and lifecycle receipts. | OCaml runtime values, Dynlink, host-private compiler objects, target-specific lowering. |
| Target semantics | target package such as `reflaxe.ocaml` | Representation, lowering, runtime requirements, printing, target diagnostics, and artifact semantics. | Host activation, compiler probing, private context mutation, shell-specific repair. |
| Typed native OCaml interoperability | `reflaxe.ocaml`, owned by `haxe_ocaml-v8a9b` | Exact Haxe declarations for representable OCaml APIs, checked adapters for advanced types, package/link metadata, and deterministic rejection. | Compiler-host privilege or a blanket mirror of private Haxe compiler modules. |
| Stock public target adapter | generic Reflaxe and target package | Public macro/Reflaxe activation and complete typed-program capture. | Claims of built-in platform or private generator registration. |
| Exact stock eval profile | separately versioned/generated host package | Exact eval-value conversion, registration, host preflight, current-request binding, lifecycle, and admitted exact-profile services. | Portable target semantics or broad private compiler access. |
| `hxhx` target host | `hxhx` | Compatible baseline facts/actions, plugin and builtin activation, request isolation, and negotiated extensions. | Upstream private OCaml layout or target lowering. |
| Compiler-transform profile | Stage4/customization owner | Declared hook phases and validated bounded rewrites. | Backend emission authority or implicit mutation through a target service. |
| Packaging/profile tooling | M22 | Exact identities, generated shells, profile extraction/diff, manifests, install/rollback, trust policy, and evidence. | Target semantics. |

## Proposed package layering

Names are architectural placeholders, not published package names.

### `reflaxe.target.api`

Generic Reflaxe should eventually own:

- target/schema/core identity;
- immutable target request and final program/facts snapshot;
- typed capability requirements;
- negotiated bounded services;
- diagnostics, result, output/build plan, and lifecycle receipts;
- canonical encoding and replay rules; and
- size, ordering, normalization, and unknown-field behavior.

It must not expose `Dynamic`, `Obj.t`, raw OCaml values, compiler objects,
ambient filesystem mutation, environment lookup, or Dynlink.

### `reflaxe.ocaml`

The target package owns one semantic OCaml target core. Evaluated stock Haxe,
stock native acceleration, an `hxhx` plugin, and an `hxhx` builtin must
eventually invoke that core. The independent Stage3 emitter remains a bounded
bring-up lane until `haxe_ocaml-38gsp.1` retires it from product evidence.

### `reflaxe.ocaml.native`

This conceptual layer owns ordinary OCaml interop such as selected `Stdlib`,
`Bytes`, `Buffer`, collections, exceptions/backtraces, `Unix`, `Gc`, `Dynlink`,
typed package interfaces, and checked adapters for OCaml types Haxe cannot
represent directly. Exact members are admitted by real consumers and
toolchain-pinned tests.

### Exact stock profiles

Exact host packages use hard-separated identities, for example:

```text
stock-haxe/4.3.7/e0b355c6.../<ocaml-profile>/<adapter-schema>
stock-haxe/5-development/<exact-commit>/<ocaml-profile>/<adapter-schema>
```

The first distribution model is deterministic local generation or
user-compiled adapters against the installed host. Separately distributed
profiles require a provenance and legal decision.

### `hxhx` host profiles

`hxhx` supplies a baseline target adapter and a separate transform adapter.
Plugin and builtin activation instantiate the same public target contract.
`hxhx` extensions use typed versioned capability negotiation instead of raw
compiler objects.

## Capability and ABI rules

Requirements have three classes:

- `required-semantic`: absence or mismatch fails before target-core creation;
- `optional-optimization`: absence selects a tested same-semantics fallback;
- `optional-tooling`: absence disables only reports or tracing.

The durable semantic data boundary is a versioned, immutable, cross-runtime
schema. Exact OCaml shells may use direct OCaml values internally while
adapting that schema. An in-process builtin may use generated typed direct
calls as an optimization, but the canonical encoded path remains available for
conformance and replay.

A narrow C-compatible dispatch table or helper process may become another
transport. Neither becomes a second semantic API.

Calls across the boundary are batched. Per-expression, per-field, or
per-position service chatter is rejected. Batch program facts, bodies or
content-addressed blobs, source tables, resources, initialization,
dependencies, reachability, diagnostics, output registrations, cache
operations, and cancellation checks.

## Exact host identity

Preflight must account for all compatibility-critical facts before Dynlink:

- host family, exact Haxe version/commit/build/executable identity;
- OCaml compiler/runtime/mode/build flags;
- operating system, architecture, ABI, loader format, word size, and endian;
- imported module/interface digests and linked package identities;
- native plugin ABI and activation kind;
- Reflaxe, target API, service catalog, and target-core identities;
- adapter generator, generated inventory, shell, and native artifact digests;
- trust/signature policy and build provenance.

A version string alone is not sufficient. A mismatch fails before loading and
names the exact expected/actual fields plus a supported regeneration command.
There is no silent semantic fallback.

## Lifecycle and failure contract

A native worker is bound to one exact host profile. Artifacts use immutable
content-addressed paths because the upstream eval loader caches adapted paths.

The host:

1. validates profile, toolchain, schema, shell, core, and service identities;
2. loads or instantiates the host adapter;
3. obtains and freezes the capability catalog;
4. rejects required mismatches before target-core creation;
5. creates a request-scoped session over one immutable program revision;
6. runs the target with bounded diagnostics, cancellation, and output actions;
7. seals the session and publishes output only through the host transaction;
8. clears request-owned references on success, failure, or cancellation.

Dynlink initialization is treated as non-transactional and non-unloadable. If
loading or initialization might have side effects and then fails, the worker is
poisoned and restarted.

The stock eval profile also needs a negative two-plugin fixture. Upstream keeps
process-global registration state, so plugin B must not accidentally accept a
stale registration from plugin A. Every activation receipt includes a unique
plugin identity and nonce; missing or mismatched registration poisons the
worker.

## Provenance and licensing boundary

Use upstream Haxe 4.3.7 as behavior, lifecycle, architecture, and interface
evidence. Do not copy, translate, retype, or mechanically rewrite GPL compiler
implementation into the MIT candidate.

The default decision order is:

1. express the capability from public behavior, public macro/Reflaxe data, or
   an MIT declaration;
2. replace compiler-owned private access with a narrow versioned host service;
3. when an exact private interface is genuinely necessary, generate the
   smallest adapter locally from the installed host's interface metadata;
4. distribute exact private-derived profiles only after an explicit license
   and legal review; and
5. reject broad or convenience-only private access.

Each generated profile records upstream identity, exact input interfaces and
digests, license class, generator identity and source digest, regeneration
command, Haxe/OCaml/Dune/platform identities, generated inventory/digests,
capability dispositions, and distribution decision.

## Required sequence

The checkpoint preserves the six-month roadmap order:

1. `haxe_ocaml-38gsp.1` hard-cuts native `hxhx` to the authentic standalone
   `reflaxe.ocaml` target core.
2. `haxe_ocaml-38gsp.2` compiles that target through itself, runs it with
   stage0 forbidden, and generates a behaviorally equivalent successor.
3. Exact Haxe 4.3.7 profile extraction, raw-plugin parity, lifecycle, and
   shared-core dual-shell research produce executable evidence.
4. M22 implementation begins only after Full1 and both authentic target
   prerequisites.
5. A later focused review selects the actual ABI version, first supported
   profile, package split, and public go/no-go.

Full1 remains the strict `hxhx` compatibility/release owner and does not gain a
dependency on the OCaml target hard cut. The dependency points in the other
direction: M22 waits for Full1.

## Bounded future work

The reviewed M22 graph adds these evidence owners:

1. exact Haxe 4.3.7 host-profile extraction, compatibility diff, and provenance;
2. handwritten-OCaml versus Haxe-authored raw-plugin parity;
3. stock eval lifecycle, server reset, stale registration, and worker poisoning;
4. one semantic core through stock and `hxhx` shells, plus plugin/builtin
   conformance;
5. a non-blocking one-container feasibility experiment;
6. licensing/distribution disposition for exact host profiles; and
7. canonical ABI fuzzing and replay.

Planning and isolated extractor experiments may happen before Full1. They do
not authorize product implementation, package publication, or a readiness
claim.

## Evidence before another review or public wording

Another focused ABI/package review becomes useful only after:

- `38gsp.1` authentic hard-cut evidence;
- `38gsp.2` two-generation stage0-free self-promotion;
- an exact Haxe 4.3.7 profile inventory and deterministic generator/diff;
- the handwritten and Haxe-authored parity pair;
- shared-core dual-shell identity/import/linkage results;
- repeated-request lifecycle/reset/stale-registration results;
- canonical versus optimized plugin/builtin conformance;
- phase-separated performance measurements; and
- a draft licensing/distribution disposition.

Until then, current manifest-v1 artifacts remain host-specific predecessor
evidence. M22 stays deferred, current public guides continue to say
experimental/planned, and README Goals bars do not move.
