# Haxe-Authored Native Plugin and Target SDK Plan

- Status: architecture review candidate; no support or readiness claim
- Prepared: 2026-07-18
- Compiler-transform owner: `haxe_ocaml-h5jta.1`
- Backend/target owner: `haxe_ocaml-bomhr` (M22)
- OCaml lowering-quality owner: `haxe_ocaml-9v1va`
- OCaml ecosystem/interoperability owner: `haxe_ocaml-v8a9b`
- Authoring-workflow owner: `haxe_ocaml-1hd2w`
- Iteration-latency owner: `haxe_ocaml-850ii`
- Native compiler comparison owner: `haxe_ocaml-i69n4`

This plan turns one product goal into two precise developer experiences:

1. Write a compiler plugin in Haxe, compile it to native OCaml with
   `reflaxe.ocaml`, and load the same semantic payload from stock Haxe 4.3.7
   and `hxhx`.
2. Write a Reflaxe compiler/target in Haxe, use it in the normal evaluated
   development lane, then promote the same target core to a native plugin or
   builtin `hxhx` target without rewriting it in OCaml.

The two experiences share build, ABI, packaging, inspection, and release
tooling. They do not share one vague compiler API. Compiler-transform plugins
run during the macro/hook lifecycle and can inspect or replace typed bodies.
Target plugins run after that lifecycle against a frozen backend program and
emit artifacts.

This is a planning contract. It does not mean that either cross-host native
profile is available today, and it does not move a README readiness bar.

## Product promise

The intended product is more powerful than a convenient transpiler or plugin
packager. Haxe plus `reflaxe.ocaml` and `hxhx` should become the best practical
compiler-authoring stack for developers who want OCaml as the deployment
runtime and ecosystem:

- **iterate quickly:** author the compiler in approachable, typed Haxe; use the
  evaluated Reflaxe lane for rapid experiments; rebuild only affected OCaml
  units and focused native artifacts as the implementation stabilizes;
- **use the OCaml ecosystem deeply:** consume ordinary libraries through typed
  facades and generated bindings, reach compiler-libs and advanced facilities
  through checked adapters when necessary, and retain explicit low-level escape
  hatches without making raw OCaml the default API;
- **ship like a native implementation:** generate readable, idiomatic OCaml,
  use compatibility runtime code only for named Haxe semantic requirements,
  compile with the native OCaml toolchain, and compete with well-designed direct
  OCaml, Go, or Rust compilers on equivalent behavior and workloads.

These legs are inseparable. Fast prototyping followed by a hand rewrite in
OCaml fails the promotion goal. Native output that cannot use the OCaml
ecosystem fails the interop goal. A loadable binary with unexplained boxing,
runtime calls, unsafe casts, poor code shape, or uncompetitive performance fails
the native-quality goal.

The architecture should therefore be as powerful as the real workload needs:
one typed target core, stable identities, explicit lowering and validation,
deterministic passes and analyses, incremental caches, and inspected target
artifacts. It should add those mechanisms when they establish a concrete
invariant, not copy the shape of another compiler for appearance. The final
experience must be judged against a carefully designed native compiler, not
against the lower bar of successful source generation.

### Why this proof matters beyond compilers

The SDK is a compiler-focused stress test of a more general Haxe advantage.
For any Haxe-authored application, library, tool, server, or plugin, native
promotion should preserve the Haxe implementation and let the selected Reflaxe
target perform the broad translation. AI-assisted development should focus on
the bounded remainder—missing target semantics, typed ecosystem adapters,
packaging, diagnostics, and measured performance gaps—instead of translating
the complete program into a second language and maintaining a fork.

That leverage is credible only when the fixes are durable. Agents must change
the Haxe source, a reusable compiler/runtime owner, or a checked native adapter;
they must not patch generated OCaml. A migration receipt should report retained
Haxe source, target-specific Haxe and native code, reusable target gaps closed,
escape-hatch inventory, behavior parity, build/iteration cost, and native
quality against a credible rewrite baseline. “Haxe does most of the work” is
the intended outcome, not a fixed percentage before those receipts exist.

Compilers are useful here precisely because they are difficult. If this stack
can promote a real compiler while preserving typed-tree semantics, plugin and
native-library access, incremental iteration, readable output, and competitive
performance, simpler Haxe software should benefit from the same underlying
model. Future Reflaxe targets for Go, Rust, or C may extend that model, but each
must independently earn its semantic and performance claims.

## 1. Current truth

Stock Haxe 4.3.7 can load native OCaml plugin modules through
`eval.vm.Context.loadPlugin`. The module must match the Haxe and OCaml build
environment. The official example exposes callable native functions and
registers an after-typing callback that changes a typed field body.

That is a compiler-plugin seam, not a dynamic target-registration API. Haxe
4.3.7 still chooses targets through its closed platform and generator
dispatch. A promoted Reflaxe target can execute native target logic from the
existing Reflaxe macro/eval integration, but this must not be described as
adding a new stock-Haxe platform at runtime.

`hxhx` currently has experimental, host-specific native macro-module and
backend-plugin loaders. The existing stock-Haxe eval-host artifact and `hxhx`
native backend artifact do not implement one shared ABI and are not
interchangeable.

`../Coro` is a useful advanced reference. Its roughly two-thousand-line native
OCaml plugin registers an after-typing callback and rewrites selected typed
functions into resumable state machines while preserving locals, control flow,
exceptions, closures, and evaluation order. It proves that the desired plugin
surface must eventually support more than registration and diagnostics.

## 2. Two semantic profiles over one shared substrate

| Profile | Runs when | Receives | May return | Owner |
| --- | --- | --- | --- | --- |
| `compiler-transform/v1` | A declared Stage4 macro/hook phase, including after typing and before optimization | A candidate-bound typed snapshot plus declared services | Diagnostics and validated rewrite operations for that program revision | Stage4 and `haxe_ocaml-h5jta` |
| `backend-target/v1` | After macros/hooks complete and the backend-facing program is frozen | The M22 backend program/facts envelope plus declared services | Artifacts, build plans, and backend diagnostics | M22 backend/target registry |

The profiles share:

- Haxe-authored source compiled through `reflaxe.ocaml`;
- payload identity and reproducible source/core digests;
- ABI envelope, manifest, capability negotiation, and preflight diagnostics;
- host/toolchain fingerprints and cache keys;
- thin-loader-shell policy;
- trusted-code and provenance policy;
- build, watch, inspect, test, package, install, upgrade, rollback, and publish
  machinery;
- deterministic evidence formats.

They keep separate:

- lifecycle phase and mutation authority;
- request and response schemas;
- capability catalogs;
- invalidation rules;
- success and failure semantics.

Neither profile exposes a `Dynamic` service bag, a raw compiler context,
private upstream-Haxe values, private `hxhx` objects, OCaml object identity, or
mutable compiler globals.

## 3. Shared native artifact model

The product target is one source tree, one semantic core, one ABI version, and
one promoted payload for both hosts.

The supported reference toolchain must first attempt one identical loadable
binary. This is a proof obligation, not an assumption about OCaml dynlink.
Stock Haxe's plugin documentation explicitly ties native plugins to the same
OCaml and Haxe build environment.

If an experiment proves that the two hosts cannot load the same container
because of an exact OCaml compiler, runtime, linker, loader, or module-digest
constraint, only this fallback is allowed:

```text
stock-Haxe loader shell ─┐
                         ├─> one versioned semantic payload/core
hxhx loader shell ───────┘
```

The shells may translate loading and transport only. They cannot contain a
typed rewrite, target lowering, printer, fallback semantics, or host-specific
copy of the plugin. Evidence must record both shell digests and either the
identical payload digest or the reproducible native-core digest.

The ABI representation should be transport-independent and stable across host
implementations. The default design input is a canonical, versioned data
encoding with immutable snapshots, stable IDs, bounded opaque handles, and
coarse calls. A direct in-process representation is an optimization only after
it proves identical behavior and reset semantics against that contract.

This artifact model must also survive a future repository split. The shared
ABI, target core, and payload have one versioned source of truth; `hxhx` must be
able to validate an immutable `reflaxe.ocaml` candidate without reading a
sibling source directory. The extraction timing, candidate/pin protocol, and
tiered downstream QA contract are defined in
`docs/00-project/REFLAXE_OCAML_REPOSITORY_EXTRACTION_GATE.md`. Repository
extraction does not authorize duplicate target semantics or a second ABI owner.

## 4. Compiler-transform snapshot and rewrite model

The smallest credible cross-host transform API is a batch protocol, not a set
of callbacks over host-owned objects.

### Request

A transform request carries at least:

- ABI, schema, profile, plugin, host, and toolchain identity;
- compilation/session ID and immutable program revision;
- exact hook phase and ordering slot;
- stable module, type, field, local, declaration, and expression identities;
- semantic types, declaration references, source positions, metadata, and
  typed bodies required by the plugin's negotiated projection;
- explicitly granted read services and limits.

The host may provide a narrower projection when the plugin declares that it
does not need a complete typed program. Missing required facts fail before the
plugin runs.

### Response

A transform response contains:

- structured diagnostics with source positions;
- a deterministic patch set tied to the input revision;
- explicit replacements, additions, or metadata changes from an allowlisted
  operation vocabulary;
- preconditions for every referenced stable ID;
- optional deterministic trace/debug facts.

It never returns a host pointer or asks the host to execute an untyped string.

### Application and sealing

The host validates the whole patch before applying any part of it. Validation
checks identity, phase authority, declaration ownership, type shape,
assignability, source provenance, duplicate edits, and unsupported constructs.
A failed patch has no partial effect.

After a successful transform, the compiler creates a new program revision and
invalidates every downstream product derived from the old revision. Parsed and
typed bodies cannot silently diverge. Optimization and backend freeze consume
only the new revision.

An implementation may eventually use a richer typed-body replacement or a
host-assisted retyping service. The independent review must decide which is
sound enough for Coro-class transforms. A side table keyed by object identity,
source offset, or traversal order is not acceptable.

### Lifecycle and compiler servers

Each compilation gets an explicit plugin instance or reset event. Registration
is idempotent within that compilation and cannot leak callbacks into the next
server request. Caches are keyed by candidate, plugin payload, ABI, requested
projection, defines, classpaths, hook phase, and toolchain identity.

Cancellation, timeout, plugin crash, malformed output, stale revision, and
host shutdown have deterministic results. An in-process crash can still take
down the compiler because native plugins are trusted code; the outer developer
tool must make recovery and stale-server cleanup automatic.

## 5. Example ladder

Examples are compatibility contracts under the repository's example coverage
policy. They land only when their compile, build, load, run, and expected-output
checks can be automated.

### Example A: native compiler-plugin hello

The first public example is a small Haxe-authored equivalent of the official
Haxe plugin example. It should:

1. expose one native callable that returns a greeting;
2. accept and report one Haxe source position;
3. register one after-typing hook;
4. replace one explicitly marked method body with a constant result;
5. load the same semantic payload in stock Haxe 4.3.7 and `hxhx`;
6. produce the same diagnostics and runtime output in both hosts;
7. demonstrate generated OCaml inspection and a handwritten OCaml escape
   hatch that is present but not needed by the example.

This is the ABI and onboarding proof. It is intentionally not a coroutine
implementation.

### Example B: native Reflaxe target

The M22 example is a real, small target core in ordinary Haxe. The same core
must run through:

- evaluated upstream-Haxe/Reflaxe development;
- native stock-Haxe Reflaxe activation;
- native `hxhx` backend-plugin activation;
- builtin `hxhx` target activation.

The stock-Haxe form uses the real Reflaxe macro/eval lifecycle. It does not
claim that Haxe 4.3.7 dynamically registered a new platform.

### Example C: bounded Coro seed

The next compiler-transform proof ports one deliberately small coroutine
shape: a typed closure with one suspension and one resume value, lowered to a
state machine. It proves body replacement, generated locals, declaration
references, evaluation order, source diagnostics, and cross-host output.

Loops, nested suspension, try/catch, captured mutable locals, and arbitrary
call suspension remain explicit unsupported diagnostics at this rung.

### Example D: Coro-class plugin

The advanced acceptance workload expands the seed toward the behavior of
`../Coro`: generators, async/await, pipes, loops, closures, exceptions,
captured locals, and side-effecting expressions. Each admitted construct gets
an upstream-Haxe/Coro oracle fixture, a cross-host transform-tree assertion,
and target runtime output.

`../Coro` is MIT-licensed. A derived Haxe port may reuse it only with the
required notice, a source-to-source provenance ledger, and review of every
dependency on upstream compiler-private APIs. A behavior-based reimplementation
is also valid. Neither route may copy or translate upstream Haxe compiler
source or vendor upstream compiler tests.

## 6. Haxe-first developer experience

The SDK should have one Haxe-authored driver used by both stock-Haxe and
`hxhx` entry points. The stable launcher name is an implementation decision;
the verbs and artifact contract should not fork by host.

The intended inner loop is:

```text
init -> edit/watch -> incremental Haxe-to-OCaml compile -> incremental Dune build
     -> ABI preflight -> focused load/run in both hosts -> inspect only on demand
```

The command surface should cover:

| Need | Compiler transform | Reflaxe target |
| --- | --- | --- |
| Scaffold | `compiler-plugin init` | `target init` |
| Fast loop | `compiler-plugin dev` | `target dev` |
| Build | `compiler-plugin build` | `target build --activation plugin|builtin` |
| Inspect | `compiler-plugin inspect` | `target inspect` |
| Test | `compiler-plugin test --host haxe,hxhx` | `target test --host haxe,hxhx --activation evaluated,plugin,builtin` |
| Diagnose | `compiler-plugin doctor` | `target doctor` |
| Ship | `compiler-plugin package/install/publish` | `target package/install/publish` |

These are desired stable spellings, not claims about today's CLI. The existing
`hxhx plugin build/test` commands currently mean backend-plugin scaffolding.
When the new surface lands, use the repository's hard-cutover policy: move
backend promotion under `target`, reserve `compiler-plugin` for lifecycle
plugins, update all examples/docs together, and do not retain ambiguous aliases.

### Fast-loop rules

- Do not rebuild `hxhx`, regenerate bootstrap snapshots, or run broad repo
  guards for an ordinary plugin-source edit.
- Compile the shared payload once, then generate only manifests or proven-thin
  loader shells per host.
- Reuse compiler and Dune caches only when their full identity matches.
- Run independent host smokes in parallel after the shared payload is built.
- Show phase timings for Haxe typing, Reflaxe lowering, OCaml compilation,
  linking, plugin load, host adaptation, transform/emission, and fixture run.
- Make a cache miss explain its changed key.
- Own every spawned Haxe/compiler server by session, verify its identity before
  reuse, and terminate it on cancellation or failed startup. No process found
  by a loose name match is killed.
- Keep a one-command cold, warm, and changed-one-file benchmark under
  `haxe_ocaml-850ii` and M22.10.

### Escape hatches

Advanced authors may add small handwritten `.ml`/`.mli` modules behind typed
Haxe externs and explicit Dune declarations. The SDK should generate/check the
boundary signature and include native sources in provenance and cache keys.

Raw OCaml expression injection remains a quarantined last resort governed by
the scoped raw-injection policy. It cannot cross the host ABI, replace a
structured rewrite, or satisfy the idiomatic-output gate merely because it
compiles.

## 7. Idiomatic and efficient generated OCaml contract

The product goal is code an experienced OCaml developer can read and maintain,
with runtime support only where Haxe semantics require it. Native promotion is
not successful merely because Dune produced a `.cmxs`.

Every representative plugin/target fixture should retain:

- formatted generated `.ml` and `.mli` output;
- deterministic source maps and stable readable names;
- compiler warnings under a reviewed warning policy;
- runtime-plan and profile reports;
- generated source size, native artifact size, load time, allocations/GC where
  measurable, throughput, and peak RSS;
- a target-shape snapshot for the semantic seam under test;
- runtime behavior and diagnostic parity.

The quality rules are:

1. Prefer OCaml modules, functions, records, variants, pattern matching,
   exceptions, and tail-safe recursion/loops that match the program's real
   shape.
2. Do not emit fake Haxe class shells, pervasive `Obj.magic`, dynamic lookup,
   refs, boxing, or generic runtime calls when the typed source proves a direct
   representation.
3. Use the structured `OcamlExpr` target AST and keep the printer semantic-free.
   `ERaw` use is inventoried and allowlisted.
4. Record runtime intent during lowering and cross-check it with
   `RuntimeUsageCollector`; emitted-token scanning is debug-only.
5. A minimal native plugin should not copy or link the whole portable runtime.
   Every linked runtime module needs a recorded semantic reason and transitive
   dependency.
6. Unsupported typed constructs fail with a Haxe-facing diagnostic before the
   OCaml compiler sees plausible but incorrect code.
7. Direct-OCaml comparisons use equivalent behavior and workload. Compare
   build/load/run cost, allocation, dependencies, source shape, and artifact
   size; do not claim whole-compiler superiority from one microbenchmark.

The existing `OcamlBuilder` is still a large mixed-responsibility module.
`haxe_ocaml-9v1va` owns the first validated semantic-plan extraction. This SDK
may consume that work, but it must not invent a speculative universal IR or
delay the plugin API until a big-bang backend rewrite.

## 8. Lessons from sibling Reflaxe targets

A local 2026-07-18 audit of `../haxe.elixir.codex`, `../haxe.rust`, `../haxe.go`,
and `../haxe.ruby` supports four principles:

- build a structured target AST before printing;
- make typed semantic decisions before target syntax;
- keep runtime use deliberate and observable;
- validate generated source shape as well as executable output.

The audit also shows the cost of concentrating too much analysis and lowering
in one compiler class. The OCaml plan should reuse the principles, not copy the
siblings' mega-files or language-specific IRs. OCaml's managed memory,
exceptions, algebraic data types, and expression-oriented control flow mean it
does not automatically need the same lowering depth as Rust, Go, or C.

## 9. Work sequence and ownership

### Phase A: review and freeze boundaries

Owner: `haxe_ocaml-h5jta.1`.

- Independently review the two-profile split, stock-Haxe feasibility, ABI
  transport, typed rewrite model, Coro scope, tooling, and OCaml quality gates.
- Freeze shared versus profile-specific manifest fields.
- Decide identical-binary experiment and fallback evidence.
- Create implementation beads only after the review is integrated.

### Phase B: shared artifact and author driver

Joint substrate for `haxe_ocaml-h5jta` and M22.

- Build the Haxe-authored SDK driver, identity/cache model, inspect/doctor
  reports, package format, and host conformance harness.
- Hard-cut ambiguous backend-plugin CLI naming.
- Prove deterministic build and cleanup before adding rich semantics.

### Phase C: compiler-plugin hello

Stage4/customization owner.

- Add the minimum transform snapshot/patch projection.
- Load and execute the example in stock Haxe and `hxhx`.
- Prove revision, reset, error, and server-reuse behavior.

### Phase D: real target promotion

M22 owners `haxe_ocaml-c4czv`, `haxe_ocaml-bxwut`, and
`haxe_ocaml-zof2e`.

- Prove the real Reflaxe target across evaluated, both plugin hosts, and
  builtin activation.
- Keep stock-Haxe activation honest about the closed target registry.
- Measure the author loop under M22.10.

### Phase E: Coro seed and expansion

Stage4/customization owner, related to M22 only through shared tooling.

- Freeze provenance, licensing, and black-box behavior fixtures.
- Admit one suspension form, then expand construct-by-construct.
- Do not close on a toy seed; the final platform claim needs a Coro-class
  transform or an equivalently demanding independent plugin.

### Phase F: product documentation and support decision

- Publish a beginner tutorial, command reference, typed rewrite model,
  generated-OCaml guide, native escape-hatch guide, troubleshooting, security,
  packaging, compatibility matrix, and migration guide from handwritten OCaml.
- Gate every supported claim on same-candidate artifacts from both hosts.
- Keep compiler-plugin and backend-target support decisions independently
  revocable even though they share tooling.

## 10. Validation matrix

| Surface | Required proof |
| --- | --- |
| Source identity | One Haxe semantic core digest; no host branches in transform or target semantics |
| Stock Haxe load | Exact Haxe/OCaml/toolchain preflight, official plugin lifecycle, deterministic load failure |
| `hxhx` load | Same ABI/payload preflight and equivalent lifecycle/service catalog |
| Identical binary | Same loadable digest in both hosts on the reference toolchain |
| Loader-shell fallback | Recorded failed experiment, exact incompatibility, shell-only diff, shared payload/core digest |
| Typed snapshot | Stable IDs, semantic types, positions, deterministic projection, malformed-input negatives |
| Patch application | All-or-nothing validation, phase authority, stale-revision rejection, downstream invalidation |
| Server reuse | No callback/state leakage; explicit reset, cancellation, crash recovery, and cache identity |
| Hello example | Greeting, position, one body rewrite, same diagnostics/output in both hosts |
| Target example | Same target core across evaluated, stock plugin, `hxhx` plugin, and builtin |
| Coro seed | One suspension/resume state machine with source-shape and runtime parity |
| Coro class | Loops, captures, exceptions, nested control flow, evaluation order, and negative diagnostics |
| Generated OCaml | Formatting, warnings, readable snapshot, runtime plan, no unjustified dynamic/runtime surface |
| Performance | Cold/warm/one-file timings plus comparable direct-OCaml baseline and validated output |
| Examples | Example coverage guard plus compile/build/load/run and `expected.stdout` |
| Claims | Same-candidate aggregate, provenance, support matrix, README/North Star review |

## 11. Invariants and rejected shortcuts

Invariants:

- One payload never contains different semantics for stock Haxe and `hxhx`.
- Compiler transforms run only at declared Stage4 phases; targets run only
  after backend freeze.
- Every request, patch, and artifact is tied to an immutable candidate and
  program revision.
- A host validates complete plugin output before it changes compiler state.
- Removing a compiler plugin restores baseline output and evidence behavior.
- Plugin state, registrations, and handles do not leak across compiler-server
  compilations.
- Representation and loader packaging do not decide Haxe semantics.
- Generated OCaml runtime use is justified by tracked semantic intent.

Rejected shortcuts:

- exposing the upstream or `hxhx` compiler object as a native value;
- compiling separate stock-Haxe and `hxhx` implementations;
- calling a stock-Haxe macro plugin a dynamically registered native target;
- hiding transform hooks inside M22 backend services;
- returning raw OCaml or source strings as typed-tree patches;
- keying edits by object identity, traversal index, or source offset;
- retaining ambiguous `plugin` CLI terminology through compatibility aliases;
- using full rebuilds and broad gates as the default edit loop;
- claiming idiomatic OCaml from successful compilation alone;
- treating the bounded Coro seed as platform closure;
- using a universal IR as a prerequisite without evidence from multiple
  converging semantic plans.

## 12. Review stop conditions

Stop and redesign before implementation if the work requires:

- private compiler AST objects crossing the shared ABI;
- a mutable general compiler context;
- partial patch application;
- silent retyping or stale typed bodies;
- host-specific semantic branches inside the payload;
- loader shells containing transforms or target code;
- callbacks surviving into a later compiler-server request;
- broad `Dynamic` or `Obj.magic` fallback for typed plugin data;
- a large new subsystem inside `OcamlBuilder`, the Stage3 orchestrator, or
  another existing mega-file;
- weakening the upstream-Haxe lifecycle or parity evidence to make the plugin
  easier to load.

The independent review should return architecture guidance, invariants,
rejected alternatives, a migration sequence, and a validation plan. It should
not provide implementation code for direct transcription.
