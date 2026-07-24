# M22 Native Reflaxe Compiler SDK Plan

- Status: accepted planning contract; implementation deferred until Full1 and
  the authentic shared-target hard cut; no SDK capability or support claim
- Date: 2026-07-15; shared-host ABI amendment accepted 2026-07-18
- Owner: `haxe_ocaml-bomhr`
- Architecture contract: `haxe_ocaml-bomhr.1`
- Prerequisites: `haxe.ocaml-f1cl`, `haxe_ocaml-38gsp`
- Related owners: `haxe_ocaml-h5jta`, `haxe_ocaml-h5jta.1`,
  `haxe_ocaml-850ii`, `haxe.ocaml-vary.2`

This page is a planning contract. It describes what M22 must prove before the
repository can call the Native Reflaxe Compiler SDK supported. It does not
describe functionality available today, change an ABI version, authorize a
release claim, or increase any README readiness bar.

The six-month checkpoint keeps this design but changes its schedule. M22
implementation must not begin while native `hxhx` still reaches the independent
Stage3 OCaml emitter. `haxe_ocaml-38gsp.1` must first prove that native `hxhx`
feeds the actual standalone `reflaxe.ocaml` target implementation, and Full1
must satisfy the existing prerequisite. This prevents M22 from freezing host
services or a program envelope around a temporary second semantic target.

## 1. Plain-language goal

A target author should be able to start with normal Haxe and portable Reflaxe,
keep one target implementation, compile that implementation to native OCaml
with `reflaxe.ocaml`, and run one promoted plugin payload inside either stock
Haxe or `hxhx`. The same target core can also run inside `hxhx` as a builtin.

The default packaging goal is one identical native plugin binary for both
hosts. If an experiment proves that OCaml compiler, runtime, linker, or loader
identity makes one container impossible, M22 may generate thin host-specific
loader shells around one shared payload or reproducibly derived native core.
The shells may adapt loading and ABI transport only; they cannot own target
semantics.

Native execution alone does not give target code privileged compiler
information. M22 adds a narrow, typed, versioned way for `hxhx` to provide
backend-facing facts and services after the compiler has established the
backend program. It does not make Reflaxe the owner of parsing, name lookup,
typing, macros, or baseline compiler behavior.

In stock Haxe 4.3.7, “native plugin” means activation through the official
eval-VM plugin and macro lifecycle. Haxe 4.3.7 does not provide a stable
runtime API that adds a new platform to its closed target dispatch. The stock
M22 adapter may execute the promoted Reflaxe target core from the existing
Reflaxe macro/eval integration; it must not claim dynamic target registration.

## 2. The problem: native execution is not compiler capability

`reflaxe.ocaml` can turn Haxe-authored target code into a native OCaml
artifact. That changes how the target code executes; it does not automatically
give the artifact access to `hxhx` compiler state.

Portable Reflaxe targets normally work through the public typed/macro data
provided by upstream Haxe. An in-tree handwritten backend can sometimes rely
on additional host-owned information, lifecycle knowledge, or output services.
Without an explicit contract, a promoted Haxe target must either duplicate
analysis, use process globals, depend on unstable host internals, or silently
lose capability.

M22 closes that product gap with semantic contracts rather than a general
compiler-context object.

## 3. Current source anchors and exact gaps

| Current anchor | What exists today | M22 gap |
| --- | --- | --- |
| `packages/hxhx-core/src/backend/BackendContext.hx` | Small invocation/configuration object passed to backends. Fields are final, but contained maps/arrays are mutable and `ensureOcamlProfileDefine()` normalizes by mutation. | Keep it configuration-only and establish deterministic copy/freeze behavior. Do not turn it into a service bag. |
| `packages/hxhx-core/src/backend/TargetRequirements.hx` | ABI, GenIR, macro API, and `hostCaps:Array<String>`. | String tags do not identify a typed service, version range, requirement class, or actual host availability. |
| `packages/hxhx-core/src/backend/BackendAbi.hx` | Central v1 version checks. Host capability strings are checked only for non-empty values. | Preflight must compare typed requirements with an actual host catalog before backend creation/emission. |
| `packages/hxhx-core/src/backend/IBackend.hx`, `packages/hxhx-core/src/backend/ITargetCore.hx`, `packages/hxhx-core/src/backend/TargetCoreBackend.hx` | Current `(GenIrProgram, BackendContext)` emission contract. | A future request must separate configuration, program/facts, service access, and activation identity. |
| `packages/hxhx-core/src/backend/reflaxe/ReflaxeTargetAdapter.hx` | The same target-core factory can already be wrapped as a builtin or provider. | Extend this direction without forking target semantics. |
| `packages/hxhx-core/src/backend/GenIrProgram.hx` | Alias to `MacroExpandedProgram`; explicitly not a normalized target-neutral IR. | Add only the minimum versioned envelope/facts proven by real consumers. Do not start a universal-IR rewrite. |
| `packages/hxhx/src/hxhx/Stage3EmitSupport.hx` | Creates `BackendContext`, recovers `GenIrProgram`, and dispatches the backend. | This is the composition point for a future request and host catalog. |
| `packages/hxhx-core/src/backend/BackendDispatchBoundary.hx` | Quarantined typed/reflective bootstrap bridge. | Do not expand it into a general dynamic service API. Temporary changes need inventory and exit proof. |
| `packages/hxhx-core/src/backend/plugin/BackendPluginManifest.hx`, `packages/hxhx-core/src/backend/plugin/BackendPluginManifestParser.hx`, `docs/02-user-guide/compat/hxhx-backend-plugin-manifest-v1.schema.json` | Manifest v1 carries ABI, GenIR, macro API, entry, and target IDs. | No service API, requirement class, service-access preset, target-core identity, or host/toolchain fingerprint. |
| `packages/hxhx/src/hxhx/NativeBackendPluginHost.hx`, `packages/hxhx/src/hxhx/NativeBackendPluginDynlink.hx`, `packages/hxhx/src/hxhx/NativeBackendPluginHostAbi.hx` | Narrow `#if reflaxe_ocaml` runtime seams and typed Haxe validation over an encoded snapshot. | Reuse this boundary style; do not assume arbitrary Haxe object identity survives OCaml dynlink. |
| Current upstream eval-host manifest and `hxhx` backend manifest | Separate v1 host contracts explicitly record that their native artifacts are not cross-host compatible. | Hard-cut to one M22 ABI and payload contract. Preserve current-v1 statements only as honest descriptions of what works before that cutover. |

The existing boundary contracts remain controlling inputs rather than being
rewritten by this plan:

- `docs/00-project/ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`;
- `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`;
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`;
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`;
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`;
- `docs/00-project/HAXE_AUTHORED_NATIVE_PLUGIN_TARGET_SDK_PLAN.md`.

## 4. Supported dimensions and named presets

M22 keeps four dimensions separate. Calling all of them “profiles” would
conflict with the existing `ocaml_profile=portable|metal` output contract and
would hide important compatibility differences.

### Execution form

- **evaluated**: target code runs through the upstream Haxe/Reflaxe development
  path;
- **native**: the same ordinary Haxe target code is compiled through
  `reflaxe.ocaml` into an OCaml artifact.

### Service access

- **host-neutral**: only data and behavior valid in the portable contract are
  visible;
- **capability-integrated**: declared, negotiated host facts/services are
  visible. `hxhx` may provide more services than stock Haxe, but both hosts use
  the same catalog and negotiation protocol.

### Activation and packaging

- stock-Haxe native plugin;
- `hxhx` native plugin using the same payload;
- `hxhx` builtin;
- evaluated upstream Haxe/Reflaxe development adapter.

### OCaml output profile

- existing `portable` or `metal` code-generation/runtime policy;
- independent from execution form, service access, and activation.

The supported named presets are therefore combinations:

| Preset | Execution | Service access | Activation |
| --- | --- | --- | --- |
| `evaluated-host-neutral` | evaluated | host-neutral | upstream Reflaxe adapter |
| `native-host-neutral` | native | host-neutral | native artifact without privileged services |
| `stock-haxe-plugin` | native | host-neutral or negotiated supported capabilities | stock-Haxe plugin |
| `hxhx-integrated-plugin` | native | capability-integrated | `hxhx` plugin using the same payload |
| `hxhx-integrated-builtin` | native | capability-integrated | `hxhx` builtin |
| `unsafe-exact-host` | native | unversioned/internal research only | quarantined adapter |

The first five presets are intended product forms once their evidence exists.
The unsafe preset is not a supported SDK surface.

## 5. Conceptual pipeline

```text
stock Haxe program/facts + services ────┐
                                        ├─> one native plugin payload ─> one Haxe TargetCore
hxhx program/facts + services ──────────┘                              └─> artifacts/build plan

same TargetCore execution forms:
- evaluated host-neutral development
- native host-neutral via reflaxe.ocaml
- stock-Haxe native plugin
- hxhx native plugin using the same payload
- hxhx builtin
```

Host adapters normalize their source data into the target-core input. They do
not own separate printers or lowering semantics.

## 6. Ownership boundary

| Layer | Owner | M22 rule |
| --- | --- | --- |
| Parse, resolve, type, module graph, baseline diagnostics | Stage3/compiler core | No Reflaxe framework dependency and no M22 hook. |
| Supported macro lifecycle and upstream-compatible after-typing/on-generate behavior | Stage4 macro host | Remains outside M22 services. |
| General policy hooks, diagnostics customization, language variations, baseline-evidence exclusion | `haxe_ocaml-h5jta` | M22 may reuse vocabulary, but does not absorb this platform. |
| Backend-facing program freeze, target selection, emission | backend registry/target core | M22 begins here. |
| Immutable backend facts and capability-limited backend actions | M22 | Typed, versioned, negotiated, and batch-oriented. |
| Release-grade stage0-free `hxhx + reflaxe.ocaml` product route | `haxe_ocaml-38gsp` | Prerequisite for supported native SDK packaging. |
| Durable iteration-latency measurement policy | `haxe_ocaml-850ii` | M22 supplies only its SDK workload/report. |

Pre-backend phase providers are not part of M22 v1. If a target needs to
change reachability, typing, macro ordering, or the program before it is
frozen, that need must be designed under Stage4 or `haxe_ocaml-h5jta` with a
separate xhigh decision. M22 may consume the resulting immutable fact; it may
not smuggle the phase hook through a backend service.

## 7. Facts, services, phase providers, and unsafe internals

### Immutable facts

Compiler-owned, deterministic snapshots that describe the frozen backend
program. Examples include stable module/type/field IDs, declared resources,
and a final reachability/retention view. Facts are immutable and batched.

### Host services

Capability-limited actions owned by `hxhx`, such as structured diagnostic
submission, telemetry spans, or artifact/build-plan registration. Each service
declares side effects, determinism, lifecycle, concurrency/server-reuse rules,
error/cancellation behavior, and authority.

### Pre-backend phase providers

Callbacks that could affect typing, macros, DCE, or program construction. They
are not M22 v1 services. The customization/variation or Stage4 owner must
design them explicitly.

### Unsafe internals

Raw compiler records, mutable globals, OCaml module values, or exact-host
object pointers. They may be used only in quarantined research and cannot
satisfy an M22 support marker.

## 8. Provisional request and service model

The exact Haxe names remain provisional until M22.2 implements the hard
cutover. The accepted shape is:

```text
BackendRequest
  configuration     frozen invocation configuration
  program            versioned backend program envelope
  facts              immutable, versioned snapshot catalog
  execution          evaluated | native
  serviceAccess      host-neutral | capability-integrated
  activation         evaluated-adapter | stock-haxe-plugin | hxhx-plugin | builtin
  targetCore         stable ID + version
  services           negotiated opaque host handle/catalog
```

Requirements use typed IDs and version ranges and are classified as:

- `required-semantic`: absence or incompatible data fails before target
  execution;
- `optional-optimization`: absence selects a semantics-preserving fallback;
- `optional-tooling`: absence disables a non-semantic tool/report feature.

The host publishes a canonical catalog and computes a negotiation result before
backend creation. Unknown IDs, duplicate declarations, malformed versions, and
missing required semantics are deterministic errors.

### Native-boundary representation decision

M22 defaults to canonical versioned snapshots plus an opaque host handle with
generated/typed wrappers. Builtins may use an in-memory typed implementation,
but it must have the same observable contract and snapshot fixtures as the
plugin path.

Direct generated-Haxe object/interface passing across OCaml dynlink is rejected
as a planning assumption. M22.2 may adopt it only after a focused proof covers:

1. separately compiled host and plugin artifacts;
2. native and bytecode hosts where claimed;
3. type identity and method dispatch across compatible and mismatched builds;
4. unload/reload or repeated compiler-server sessions;
5. deterministic rejection after toolchain/ABI mismatch;
6. plugin and builtin parity.

No per-expression service call is allowed across the dynlink boundary.

### First privileged semantic candidate

The first candidate is `backend.reachability-snapshot/v1`, a read-only batched
snapshot of the final backend-visible retained set using stable IDs and
documented retention reasons where the host can prove them.

This candidate comes from real target pressure rather than a synthetic desire
for deeper access:

- the pinned Reflaxe Elixir target uses `@:keep`, global build macros, and
  after-typing registration so convention-called modules and functions survive
  DCE;
- `hxhx` currently documents its macro include ledger as not modeling full
  typed reachability or DCE;
- a target cannot treat a guessed retained set as correctness evidence.

The snapshot does not grant authority to add roots or alter DCE. The
host-neutral fallback remains explicit source metadata/root registration
through supported public macro APIs. If the target requires an exact snapshot
and none exists, it fails before emission with a required-service diagnostic.
M22.6 must prove that this snapshot closes a real decision in one promoted
target and one builtin consumer; otherwise it must reject the candidate and
select a better evidence-backed semantic fact.

## 9. Conditional compilation and the “two-in-one” target

One source package may provide multiple composition roots, but it must keep one
semantic target core.

Allowed conditional sites:

- host adapter selection;
- native transport/extern declarations;
- service-access preset selection;
- an optimized implementation with a proven equivalent fallback;
- explicit integrated-only feature registration.

Forbidden sites:

- semantic lowering and printer branches chosen by `#if reflaxe_ocaml`;
- parser, resolver, typer, or baseline diagnostic ownership;
- hidden fallback from required semantic data to an approximation;
- plugin-only and builtin-only target implementations.

M22.5 adds a guard over each pilot target core and its lowering/printer modules.

## 10. ABI, manifest, artifact, and cache policy

Current backend and manifest v1 behavior remains current truth until M22
implementation. Planning does not bump any version.

The implementation uses a hard cutover to a versioned request/manifest
contract. It must not leave permanent v1/v2 runtime dispatch. A bounded source
migration helper is acceptable; an old native manifest must eventually fail
with an actionable migration diagnostic.

Preflight identity includes:

- manifest schema and backend ABI;
- backend program/facts version;
- macro API and host-service API versions;
- service requirements and service-access preset;
- target-core ID/version;
- host kind, version/commit, and artifact fingerprint;
- OS, architecture, OCaml version, artifact kind, source digest, and profile;
- shared plugin payload, optional loader shell, and emitted artifact digests
  plus provenance.

Source-distributed native rebuild/cache keys include every compatibility input
above. A cache hit cannot cross an unproven host/toolchain identity.

## 11. Stock-Haxe plugin and packaging policy

Upstream Haxe remains the stable host-neutral development and behavior
baseline. M22 also requires a native stock-Haxe plugin host for the same ABI and
payload used by `hxhx`.

The stock-Haxe host uses `eval.vm.Context.loadPlugin` and the real
macro/Reflaxe lifecycle. It does not register a new Haxe platform. Target
selection and invocation remain an adapter concern at the existing Reflaxe
activation seam, while target semantics stay in the shared payload.

- Haxe version, OCaml version, ABI version, and host fingerprint are checked.
- Handwritten OCaml is limited to host conversion, loading, and transport glue.
- The Haxe target core and promoted payload remain one implementation.
- The supported reference toolchain must first attempt to load one identical
  plugin binary in both hosts.
- A different loader shell is allowed only after an evidence record identifies
  the exact OCaml compiler, runtime, linker, or loader incompatibility.
- Any loader shell must open the same payload digest or a reproducibly derived
  native core digest and must pass the same conformance fixtures.
- Private upstream-Haxe AST values and private `hxhx` objects never cross the
  ABI.
- If stock Haxe lacks a required negotiated capability, loading fails before
  target execution; the plugin cannot substitute a second implementation.

Current manifest v1 and eval-host artifacts still record
`crossHostBinaryCompatibility=false`. That remains an accurate current-state
statement, not the M22 product design. M22 performs a hard cutover once the new
ABI and loader exist; it does not relabel the old artifacts as compatible.

## 12. Workstreams

The IDs below are the canonical Beads owners for M22 implementation and proof.

| Workstream | Bead | Priority | Primary blockers |
| --- | --- | --- | --- |
| M22.1 Freeze contract and boundaries | `haxe_ocaml-bomhr.1` | P1 | none; planning only |
| M22.2 Request and host-service ABI | `haxe_ocaml-edvhw` | P1 | Full1, M22.1 |
| M22.3 Minimum backend program/facts envelope | `haxe_ocaml-fa0zh` | P1 | Full1, M22.1 |
| M22.4 `hxhx` services v1 and negotiation | `haxe_ocaml-6be63` | P1 | M22.2, M22.3 |
| M22.5 Host-neutral and integrated adapters | `haxe_ocaml-seg17` | P1 | M22.4 |
| M22.6 Prove one privileged semantic fact | `haxe_ocaml-u6q8k` | P1 | M22.3, M22.4, M22.5 |
| M22.7 Manifest/service negotiation v2 | `haxe_ocaml-le0ox` | P1 | M22.2, M22.4 |
| M22.8 Shared stock-Haxe/`hxhx` native plugin ABI | `haxe_ocaml-c4czv` | P0 | M22.5, M22.6, M22.7; required |
| M22.9 Real Haxe-authored compiler proof | `haxe_ocaml-bxwut` | P1 | M22.5, M22.6, M22.7 |
| M22.10 Author-loop measurement | `haxe_ocaml-i69n4` | P2 | M22.9 |
| M22.11 Scaffolding, migration, and support matrix | `haxe_ocaml-zof2e` | P1 | M22.7, M22.9 |
| M22.12 Evidence aggregate and support decision | `haxe_ocaml-157t1` | P0 | M22.6, M22.8, M22.9, M22.10, M22.11, `haxe_ocaml-38gsp` |

M22.2 through M22.12 are implementation/evidence contracts derived from this
accepted M22.1 boundary. Their detailed acceptance criteria remain changeable
only through explicit xhigh review; creating them does not make them current
work or a support claim.

## 13. Dependency graph

```text
M22.1 + Full1 --> M22.2
M22.1 + Full1 --> M22.3
M22.2 + M22.3 --> M22.4 --> M22.5
M22.3 + M22.4 + M22.5 --> M22.6
M22.2 + M22.4 --> M22.7
M22.5 + M22.6 + M22.7 --> M22.8
M22.5 + M22.6 + M22.7 --> M22.9 --> M22.10
M22.7 + M22.9 --> M22.11
M22.6 + M22.8 + M22.9 + M22.10 + M22.11 + haxe_ocaml-38gsp --> M22.12
```

Beads representation note: the installed CLI does not allow task
`haxe_ocaml-38gsp` to block epic `haxe_ocaml-bomhr`. The epic therefore relates
to that prerequisite, while the enforceable blocking edge is
`haxe_ocaml-157t1` (M22.12) to `haxe_ocaml-38gsp`. No duplicate epic was created.

## 14. Proof and evidence matrix

| Claim | Required evidence |
| --- | --- |
| One target core | Source/core identity plus guard showing no host imports or semantic conditionals. |
| Evaluated vs native host-neutral parity | Same fixture and target-core version; byte equality where deterministic, otherwise a declared deterministic normalizer plus runtime equality. |
| Plugin vs builtin parity | Same request/facts/service catalog and target core; normalized artifact and runtime equality. |
| Stock Haxe vs `hxhx` plugin parity | Same ABI, payload digest, target-core identity, declaration decisions, diagnostics, normalized emitted artifacts, and runtime behavior. |
| Loader-shell fallback | Failed identical-binary experiment plus exact incompatibility, shell digests, shared payload or reproducible-core digest, and proof that shells contain no target semantics. |
| Required semantic service | Positive negotiated case and pre-execution failures for missing, stale, malformed, and wrong-version data. |
| Optional services | Proven semantics-preserving fallback or tooling-only disablement. |
| Real target | Pinned external or repo-owned nontrivial compiler family; no toy-only closure. |
| Native artifact compatibility | Host/toolchain/ABI/profile/core/digest preflight before dynlink where possible. |
| Supported M22 claim | Aggregate opens the actual same-candidate per-form summaries and validates their identities and digests. |

Every proof summary records candidate commit, run/attempt, execution form,
service access, activation, stage0 policy, host fingerprint, service catalog
digest, ABI versions, target-core identity, shared plugin payload digest,
loader-shell digest where applicable, emitted artifact digest, and runtime
result.

## 15. Performance method

M22.10 extends the durable latency framework rather than inventing another
policy owner. Sequential same-machine measurements separate:

1. host/compiler preparation;
2. target-core native build;
3. plugin load;
4. backend program/facts adaptation;
5. service negotiation/snapshot creation;
6. target analysis/lowering;
7. emission;
8. downstream build/run;
9. honestly scoped peak RSS.

Runs use warmup, repeated raw samples, medians, toolchain metadata, and artifact
hashes. Correct output is validated before a timing is accepted.
`native-host-neutral` isolates native execution benefit from privileged-service
benefit. A direct OCaml comparison is included only for a precisely equivalent
hot path and cannot be generalized to the whole compiler. Evidence is
report-only until a separate decision bead defines a threshold.

No “native is faster” or “same performance as handwritten OCaml” claim is
allowed without controlled evidence.

## 16. Security and trust model

Native plugins are trusted in-process code. They can use the process and
filesystem authorities available to `hxhx`; the service API is not a sandbox.

The SDK still limits accidental authority:

- target code receives declared service handles, not global compiler state;
- each service documents side effects and lifecycle;
- snapshots are immutable and candidate-bound;
- source lookup and caches require explicit roots/session identity;
- repeated compiler-server sessions cannot reuse stale handles or facts;
- malformed or incompatible native artifacts fail before loading where
  metadata permits.

Out-of-process execution or sandboxing is a future transport and is not an M22
closure blocker.

## 17. Non-goals

M22 does not authorize:

- a compiler-wide normalized or universal IR;
- a raw mutable compiler context;
- Reflaxe ownership of parser, resolver, typer, module graph, macro lifecycle,
  baseline diagnostics, or core semantics;
- pre-backend phase providers hidden inside backend services;
- conditionals scattered through semantic lowering or printers;
- assuming that one `.cmxs` works in both hosts without the required identical-
  binary experiment and exact OCaml/Haxe/toolchain compatibility evidence;
- permanent v1/v2 ABI compatibility;
- sandboxed untrusted native plugins;
- a performance claim without controlled evidence;
- public SDK/readiness wording from planning, scaffolding, or toy fixtures.

## 18. Closure marker and public-claim rule

M22.12 may emit:

```text
M22_REFLAXE_NATIVE_COMPILER_SDK:PASS
```

only after it opens and validates the real same-candidate proof artifacts for
the declared supported forms, service behavior, real target, packaging, and
performance report. Job-result strings or synthetic summaries cannot create
the marker.

README, North Star, and user-guide wording may move from planned/no-go to
supported only after that exact-candidate aggregate passes and a written xhigh
second-pass review authorizes the claim. Planning alone leaves all readiness
bars unchanged.
