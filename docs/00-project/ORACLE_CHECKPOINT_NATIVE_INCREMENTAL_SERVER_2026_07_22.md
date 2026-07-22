# Oracle Checkpoint: Native Incremental Compilation Server

Prepared: 2026-07-22

Status: GPT-5.6 Pro architecture review accepted; the first transport-ownership
sub-slice is implemented, while the larger cache-free request-lifecycle Bead
remains open

Owning Bead: `haxe_ocaml-850ii.32`

Related Bead: `haxe_ocaml-850ii.33`

Decision trail:
[`NATIVE_INCREMENTAL_SERVER_DECISIONS.tsv`](NATIVE_INCREMENTAL_SERVER_DECISIONS.tsv)

## Outcome

At the reviewed commit, the native `hxhx` process could remain open and receive
more than one request, but it was not a complete incremental compiler:

- standard-input compile requests call the real compiler again for every
  request;
- standard-input display requests return bring-up responses rather than the
  full compiler result;
- socket requests entered a separate OCaml bridge that returned display
  placeholders and rejected ordinary compilation; and
- no production cache currently proves which parsed or typed modules are safe
  to reuse.

The accepted destination is one long-lived server that owns reusable,
read-only compiler results and creates a fresh mutable working area for every
request:

```text
stdio or socket request
  -> one transport-neutral dispatcher
  -> one native hxhx compiler pipeline
  -> fresh request state + exact reusable read-only facts
  -> staged output and cache candidates
  -> validate everything
  -> publish only after success
```

Here, a **request state** is the temporary working data for one compile or
editor operation: diagnostics, current options, module-loading progress,
macro registrations, feature analysis, target buffers, and staged output. It
must not leak into the next request.

A **reusable fact** is a completed read-only result, such as a parsed source
module or a fully checked typed module. It may cross requests only when its
complete identity proves that the source, configuration, dependencies,
compiler, plugins, and relevant toolchains still match.

The first implementation slice does not add such reuse. It first makes stdio
and socket requests enter the same compiler owner and proves that repeated
requests without caching behave exactly like separate compiler processes.
Only then do later slices add source, parser, dependency, typed-module, display,
plugin, target, and memory layers.

The first implemented sub-slice removes that socket-only compiler behavior.
Both transports now create the same copied request record, use the same Haxe
decoder, and ask the same Haxe dispatcher whether the request is a compile or
an editor/display operation. The OCaml bridge only accepts a socket frame,
calls the Haxe function it was given, and returns the reply bytes. A native
socket request now compiles an ordinary Haxe program and can produce a runnable
target artifact.

That is a bounded transport capability, not incremental compilation. The
current dispatcher still calls the existing `runOne` routine, compiler output
is not yet captured per client request, display remains the bring-up response,
there is no explicit request context or cancellation transaction, and no
semantic result is cached. `haxe_ocaml-850ii.32.1` therefore remains open.
README and North Star readiness percentages remain unchanged.

## Two Connected Workstreams

This architecture affects two different server routes. They share identity,
invalidation, target-state, output, and performance principles, but one does
not automatically fix the other.

### 1. Use upstream Haxe 4.3.7's server effectively

Upstream Haxe already performs real parser and typed-module reuse. The measured
`hxhx` source-generation workload fell from 833.30 seconds on its cold request
to a 30.37-second warm request against the same Haxe server process.

Haxe 4.3.7's public macro lifecycle already distinguishes the two views that
matter here:

- `Context.onAfterTyping(callback)` receives the types completed in that typing
  batch and may run again when a callback causes more types to load;
- `Context.onGenerate(callback)` receives the complete `ctx.com.types` list,
  but Haxe still performs DCE and post-DCE body rewrites after this callback;
- `Context.onAfterGenerate(callback)` runs after those built-in filters, so it
  is the current point where Reflaxe can copy the final retained declarations
  and function bodies.

Reflaxe currently registers `onAfterTyping`, replaces its stored array with the
latest batch, and later starts target generation from that array. It therefore
treats an incremental callback payload as a complete program. The host already
supports a complete generation view; the framework adapter is not consuming it
correctly yet.

The warm Haxe process correctly reused unchanged typed modules and reported
only the newly typed batch through `onAfterTyping`. Reflaxe then incorrectly
treated that batch as the entire program. This is especially visible in
`reflaxe.ocaml`, which owns whole-program output such as the complete generated
module set, runtime selection, type registries, Dune files, reports, public
artifacts, and deletion of stale files. A new target invocation could not
reconstruct that complete state from the latest batch and stopped at the
`HxPos` ownership diagnostic.

`haxe_ocaml-850ii.33` owns this route. Reflaxe needs a target-neutral contract
that provides either:

- a complete revisioned program snapshot on every target invocation; or
- a durable exact-revision target snapshot plus validated module additions,
  changes, and deletions.

The first framework experiment should retain the complete type-object set seen
by `onGenerate`, then wait until `onAfterGenerate` to enumerate the surviving
declarations and copy/normalize their final bodies. `onGenerate` is not a
post-filter body boundary. The exact callback and persistence design must be
tested rather than inferred: it must cover repeated `onAfterTyping` batches,
DCE and feature selection, warm server requests, callback ordering, failed
output, and compiler-server revisions. If a later callback can still mutate a
selected body after Reflaxe seals it, stop and redesign the boundary.

The target then builds output privately, validates complete ownership, removes
stale units through an output transaction, and publishes only after success.
Any generic Reflaxe framework change belongs in the maintained fork and must
benefit the Reflaxe family rather than encode OCaml-specific policy.

### 2. Implement the native hxhx incremental server

Native `hxhx` currently has request transport but no semantic reuse. It must
first make stdio and socket enter one native compiler, then add its own source,
parser, dependency, typed-module, display, macro/plugin, target, and memory
layers. It must remain compatible with Haxe 4.3.7's supported request protocol
and observable compiler behavior.

This route can improve on the implementation model without changing Haxe
semantics. Immutable facts, exact revisions, reasoned invalidation reports,
bounded memory, scoped reset, worker-isolated native plugins, and
transactional output are deliberate improvements over retaining one broad
mutable compiler state.

`haxe_ocaml-850ii.32` owns this route.

The two routes should eventually share the same host-neutral target/plugin
input and output-ownership contract. They do not share one host-private cache:
upstream Haxe owns its compiler cache, and native hxhx owns its own.

## Review Provenance

The review used:

- hxhx candidate: `06f06ad016d2e984ed08824f77ab03e9d9de7e74`;
- upstream Haxe 4.3.7 behavior and protocol oracle:
  `e0b355c6be312c1b17382603f018cf52522ec651`;
- review package:
  `/tmp/oracle/hxhx-gpt56-native-incremental-server-review-06f06ad0-v2.zip`;
- locally recorded package SHA-256:
  `8a94d39f8b3eb0adeda175fcf9a4d4d3f72ae61f96a4bc7e11c213ff9cc04876`;
- controlling prompt:
  `01_GPT_5_6_PRO_HXHX_NATIVE_INCREMENTAL_COMPILATION_SERVER_REVIEW_PROMPT.md`.

The response reports that the package manifest and supplied candidate and
upstream identities were verified. The reviewed candidate predates the
fail-closed warm-Reflaxe safety change at `6ee781e3`, but direct inspection of
the current source confirms that the server transport and compiler ownership
facts used by the review have not changed.

Upstream Haxe remains a behavior and protocol reference. Its source must not be
copied, translated, mechanically rewritten, or treated as implementation text
for this MIT-oriented compiler.

## Soundness Review And Precision Notes

The central recommendation is sound and matched the reviewed source:

- `Stage3WaitServer` decodes real length-framed stdio requests and calls the
  ordinary compiler routine for non-display requests.
- `Stage3Compiler.runOne` creates setup, macro, parser, resolver, typer,
  backend, and output state again for every request.
- the socket bridge in `HxHxCompilerServer.ml` owned a different request path,
  synthesized display replies, and rejected ordinary compilation;
- `TyNominalTypeId` and `TyDeclarationId` already provide useful stable
  semantic names, so the design should extend rather than replace them;
- `TypedBodyFingerprint` and `TypedModule`'s local revision protect one typed
  body's lifecycle, but they are deliberately not complete cross-request cache
  keys; and
- mutable `TyperIndex`, module-loader, macro, hook, plugin-registration, and
  target-builder state is request working data, not cache payload.

The first implementation sub-slice directly removes the third condition. Its
focused interpreter test covers copied request inputs, shared compile/display
selection, and error framing. The regenerated native compiler additionally
proves that Haxe can pass a request handler function into the OCaml socket
adapter, and the hxhx target suite proves that a socket client can request an
ordinary compile, receive success, and run the generated JavaScript. The other
conditions remain and define the next work.

The accepted review includes these qualifications:

1. **One server does not mean one mutable compiler object forever.** The server
   owns catalogs, memory policy, process workers, health, and requests. Each
   compile still gets fresh mutable compiler state.
2. **A stable name is not a complete cache identity.** `pack.Type.field` can
   name the same declaration across requests, but a digest must still prove
   which source, body, configuration, dependencies, and compiler schema it
   describes.
3. **File times are hints, not correctness.** A timestamp can tell the server
   what to inspect. Exact content and class-path resolution decide whether a
   result is still valid.
4. **Display recovery is not compile truth.** An editor request may use an
   unsaved overlay or incomplete error-recovery tree. Only a normally sealed,
   complete result may enter the shared typed-module cache.
5. **Cache publication and filesystem output cannot be hand-waved as one
   assignment.** Candidate facts and output are prepared privately. Nothing
   reusable becomes visible until semantic validation and the output
   transaction have succeeded. A failure or cancellation publishes neither.
6. **Performance is an end-to-end product result.** A high hit count is not
   enough. We measure edit to diagnostics, generated target, native build, and
   runnable artifact, with front-end reuse separated from Dune's reuse.

## Accepted Ownership Model

### Long-lived server owner

The server process owns only cross-request coordination:

- request queueing and one-at-a-time semantic execution initially;
- workspace and configuration snapshots;
- immutable artifact catalogs;
- dependency and invalidation indexes;
- memory accounting, leases, eviction, health, reset, and shutdown;
- exact macro/plugin worker realms; and
- transactional publication.

It does not parse, type, run macros, select Haxe behavior, or lower target code
itself.

### Fresh request context

Every compile or display request creates new mutable state for:

- diagnostics and output capture;
- command-line options, defines, class paths, and editor overlays;
- parser, resolver, typer, module-loader, feature, DCE, and reachability work;
- macro and hook registrations and side effects;
- temporary names and target builders;
- cancellation and deadline state; and
- staged filesystem output.

Closing the request disposes or explicitly closes all of this state.

### One semantic compiler owner

One request compiler owns source-language behavior for both stdio and socket.
Transport code only frames bytes and sends decoded requests. Cache storage only
stores already sealed results. Targets and plugins consume a complete
host-neutral program snapshot; they do not repair or reinterpret stale typing.

## Required Identities

Each reusable record has two kinds of identity:

- a **semantic name** says what it is, such as a source module, type,
  declaration, function body, plugin, or generated unit;
- a **revision** is a deterministic digest of every input required to
  interpret that named fact.

The minimum revision families are:

| Revision | What it must distinguish |
| --- | --- |
| Compiler/schema | hxhx build and the exact source, parsed, typed, plugin, target, and report formats |
| Workspace/configuration | logical project, working directory rules, ordered class paths, defines, target/profile, libraries, stdlib, resources, toolchains, and declared environment inputs |
| Source content and origin | exact bytes plus whether the file came from the project, stdlib, a library, generated input, or an editor overlay |
| Directory/resolution | file existence, negative lookups, class-path precedence, case/symlink policy, additions, deletions, moves, and new shadowing files |
| Parsed module/catalog | parser inputs, package/module declarations, imports, usings, metadata, and generated declaration inputs |
| Public API | the externally consumed type and declaration surface used to decide which dependents must be rechecked |
| Implementation/body | private implementation, typed bodies, inline bodies, constants, static initialization, macro-generated facts, and the semantic environment needed to understand them |
| Macro/plugin/transform realm | source or binary closure, ABI, toolchain, configuration, capabilities, declared observations, and security policy |
| Program/target pipeline | included module/body revisions, reachability/resources, ordered transforms, target core/profile/runtime, and generated-unit schema |

Modification time, object identity, allocation order, absolute temporary paths,
and a local incrementing integer are not sufficient revisions.

## Cache Admission Order

The server adds power in evidence-backed layers:

1. **No-cache dispatcher baseline.** Both transports use one compiler and
   fresh request state.
2. **Source, discovery, and parser reuse.** Cache exact bytes, immutable parser
   output, selected module origins, directory observations, and negative
   lookups.
3. **Dependency observation.** Record what clean compilation actually read and
   predict affected modules without reusing typed modules. A false-negative
   prediction blocks typed caching.
4. **Sealed typed-module reuse.** Reuse only immutable modules carrying
   deterministic public API, implementation, body, program, and dependency
   revisions.
5. **Display integration.** Share only complete normally sealed facts; keep
   overlays and recovery state private.
6. **Macro, plugin, and transform realms.** Continue rerunning macros at first;
   isolate changeable native code in versioned worker processes.
7. **Target plans and generated units.** Reuse exact target plans and avoid
   rewriting unchanged units while leaving OCaml object and link caching to
   Dune.
8. **Memory, reset, health, and long-run operation.** Enforce budgets, scoped
   reset, eviction, ownership, and stale-endpoint recovery.
9. **Default workflow decision.** Enable server use by default only after
   correctness, operational, and performance gates pass.

In-memory reuse is the first production architecture. A persistent typed cache
is a later, separately reviewed option. It becomes eligible only after the
in-memory model is correct and process-restart measurements show enough
remaining cost to justify a versioned on-disk format.

## Invalidation Rules

One authoritative coordinator records typed dependency edges. Separate source,
typing, macro, transform, and target graphs must not disagree about which
result is current.

The most important distinction is:

- a **public API change** rechecks dependent modules until the public surface
  stops changing;
- an **ordinary implementation-only change** rechecks the changed module but
  may keep callers whose consumed signatures are unchanged;
- inline bodies, constants, generated declarations, macro observations,
  static initialization, DCE/reachability, transforms, and target plans carry
  explicit body-sensitive edges and still invalidate their consumers.

Add, delete, rename, move, class-path reordering, and new shadowing files must
invalidate resolution facts, including prior failed lookups. Returning from
source state A to B and back to A may reuse the older immutable A record only
when its complete key still matches.

Uncertainty is always a miss or an actionable diagnostic. It is never a stale
hit, target fallback, `Dynamic`, raw code, stage0 delegation, or retained file
whose owner is unknown.

## Macros, Plugins, And Targets

Initial server policy is deliberately conservative:

- macro sessions, build macros, hooks, and arbitrary transform executions run
  again for each request;
- their file, type, resource, environment, process, and network observations
  are recorded so a later pure-cache contract can be proven;
- untracked effects make derived work ineligible for reuse;
- changeable `.cmxs` macro or plugin code is loaded into a worker process keyed
  by exact source/binary, ABI, toolchain, configuration, and policy revision;
- changing native code starts a new worker because OCaml dynlink cannot safely
  unload the prior version from the main server; and
- target lowering consumes a complete sealed target-neutral program revision
  and produces separately keyed target plans and generated units.

A fixed builtin plugin may run in the main process only when it is part of the
compiler build identity and has no untracked mutable request state.

## Memory, Concurrency, And Failure

Semantic requests are serialized initially. Parallel connection acceptance is
not permission to run mutable typing, macro, plugin, or target state
concurrently.

The memory owner records retained bytes, recomputation cost, workspace, last
use, and active leases for each cache layer. Soft pressure evicts unused facts;
active facts remain pinned. Exact shipping budgets will be chosen from measured
corpora rather than guessed in this architecture checkpoint.

A failed, cancelled, timed-out, or partially recovered request publishes no
typed or target result and commits no staged output. A worker that cannot prove
rollback is terminated. An impossible key, graph, body, or publication state
is an internal invariant failure: quarantine the suspect record, preserve
bounded evidence, optionally compare once with a clean request, and stop the
server if correctness cannot be re-established.

Reset and shutdown are scoped to owned workspace, target, or worker state.
Process PID, start identity, executable/build identity, endpoint, owner, and a
random startup nonce must match before cleanup. Broad process-name killing is
forbidden.

## Performance Product Bar

The objective is not merely to resemble another incremental compiler. The
complete Haxe-to-runnable-artifact loop should be competitive with, and where
our architecture permits, better than mature TypeScript and Go development
workflows on representative projects.

TypeScript persists project-graph/build information in `.tsbuildinfo` for
incremental and project-reference builds. Go caches compiled package outputs
and keys them by source, compiler, options, and other build inputs. hxhx should
combine precise in-memory source/parse/type reuse with immutable target-unit
reuse and Dune's native OCaml artifact cache.

Official comparison references:

- [TypeScript incremental option](https://www.typescriptlang.org/tsconfig/incremental.html)
- [TypeScript project references](https://www.typescriptlang.org/docs/handbook/project-references)
- [Go build and test caching](https://go.dev/cmd/go/#hdr-Build_and_test_caching)

“Similar or better” is a measured acceptance goal, not a readiness claim. The
benchmark matrix must report:

- cold process, cold server, unchanged warm, leaf edit, shared API edit, macro
  edit, plugin edit, target-only edit, and process restart;
- edit-to-diagnostics and edit-to-runnable-result wall time;
- p50, p95, and p99 on controlled machines;
- source probing, parse, resolution, typing, macro, transform, target
  generation, file writing, Dune compile, link, and program load separately;
- cache hits, misses, rechecks, invalidation reasons, retained bytes, eviction,
  and worker starts; and
- the same exact workload and hardware for hxhx, TypeScript, Go, and relevant
  direct-Haxe baselines, with language/project differences stated rather than
  hidden.

The server should not become the default unless it is exactly correct,
operationally bounded, and materially improves real developer time. If typed
reuse still leaves macro, hashing, target generation, or native build as the
dominant cost, phase evidence chooses the next optimization.

## First Implementation Bead

The first child of `haxe_ocaml-850ii.32` is deliberately cache-free:

> Unify native hxhx stdio and socket requests behind one protocol-neutral
> dispatcher and one fresh per-request compiler lifecycle.

Its ordered outcome is:

1. decode both transport formats into one immutable request record;
2. route ordinary supported compile and display requests through one request
   compiler;
3. construct and close fresh mutable state for every request;
4. stage output and return deterministic protocol replies;
5. add cancellation, malformed-frame, shutdown, and ownership fixtures;
6. prove fresh process, cold server, and repeated no-cache server equivalence;
7. report phase timing with semantic cache counts fixed at zero; and
8. remove the socket display-only semantic stub.

This slice must not add module cache maps, macro reuse, plugin reuse, target
reuse, persistent storage, or default enablement.

## Documentation Plan

The existing
[`COMPILATION_SERVER.md`](../01-getting-started/COMPILATION_SERVER.md) is the
truthful current-state guide. It already covers upstream Haxe setup, current
defaults, the blocked warm Reflaxe path, safe project/CI/editor workflows,
process ownership, memory, and troubleshooting.

As native slices become real, shipping documentation expands into:

- a native-server quickstart;
- a full native-server reference;
- an editor/display guide;
- a macro/plugin/target realm guide;
- an operations, security, memory, reset, and troubleshooting guide;
- updated stock-Haxe + `reflaxe.ocaml` and native-hxhx + `reflaxe.ocaml`
  routes;
- a benchmark method and revisioned results; and
- small machine-tested ordinary app, builtin target, plugin target, macro,
  display-overlay, and multi-project/toolchain examples.

No future guide may imply a capability before its implementation and smoke
test exist. Every documented command must be exercised by a docs or example
test. CLI help and server diagnostics must link users to the relevant guide
before default enablement.

## Rejected Shortcuts

- Do not call a long-lived process incremental when it only reruns a clean
  compiler.
- Do not add a filename-to-parser map inside `Stage3Compiler`.
- Do not key correctness only by filename, modification time, module name, or a
  local integer revision.
- Do not retain one broad mutable compiler, macro, or target context across
  requests.
- Do not stop at parser hits and claim production incremental compilation.
- Do not keep separate stdio and socket compilers.
- Do not let transport, targets, plugins, or Dune own Haxe invalidation.
- Do not reuse arbitrary macro results or in-process native plugin state.
- Do not introduce persistent typed storage before in-memory correctness and
  restart-cost evidence.
- Do not rely on OCaml garbage collection as cache eviction policy.
- Do not add concurrent semantic requests before isolation and measurements
  justify them.
- Do not delegate misses or errors to upstream Haxe.
- Do not keep permanent old and new semantic paths after a bounded comparison.
- Do not move README percentages for architecture, protocol, or cache-hit-only
  milestones.

## Stop And Redesign Conditions

Stop the active cache slice when any of these occurs:

- clean and warm diagnostics, output, resources, reports, exit status, or
  runtime behavior differ;
- the dependency graph predicts reuse for work that a clean build changes;
- identities vary with request order, allocation order, hash traversal, or
  machine-specific temporary paths;
- retained mutable state affects another request;
- failed, cancelled, display-recovery, or worker-crash state changes a later
  compile;
- target/profile facts cross a supposedly target-neutral cache key;
- macro or plugin effects cannot be observed or isolated;
- retained memory grows without explanation or reset cannot restore a clean
  boundary;
- worker IPC, hashing, target generation, or native building dominates without
  a material end-to-end win; or
- protocol compatibility requires two semantic compilers.

The response to these conditions is a narrower cache boundary, a more complete
identity/edge, process isolation, or a revised performance plan. It is not a
weaker correctness gate.

## Closure Conditions

`haxe_ocaml-850ii.32` closes only when:

- stdio and socket compile/display requests use one native semantic pipeline;
- supported source, parse, resolution, typed, display, macro/plugin, and target
  reuse layers pass their clean/warm differential matrix;
- invalidation has no known false negatives;
- failures and cancellations cannot publish state or output;
- memory, eviction, reset, shutdown, stale endpoints, and child processes are
  bounded and owned;
- warm unchanged and representative edits materially improve end-to-end
  developer wait time on controlled workloads;
- the comprehensive end-user, editor, extension-author, operations, and
  benchmark docs and examples are machine-tested;
- normal native operation remains stage0-free and clean-room;
- the direct clean route remains a bounded comparison and recovery command;
  and
- README progress changes only when this user-visible capability is actually
  usable and evidenced.
