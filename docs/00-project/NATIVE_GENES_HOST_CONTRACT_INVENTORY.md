# Native Genes host-contract inventory

Status: active inventory; not a native-support claim

Owner: `haxe_ocaml-bomhr.2.1`

Inspected Genes revision: `6f2e4342f0c9c0b7a68689f9556a2041857d15a9`

## What this inventory enables

This inventory identifies the smallest host behavior that a native Genes
compiler needs. It covers classic JavaScript and strict TypeScript generation.

It does not define a public ABI. It does not claim that Genes runs inside
`hxhx`. It also does not permit a Genes-specific branch in the compiler.

The inventory separates two different APIs:

- Genes macros use the normal public Haxe macro API while the host types the
  program.
- The Genes generator consumes a frozen request after typing and dead code
  elimination.

Serializing the complete macro runtime into the generator request would expose
mutable compiler authority. The future native contract must not do that.

## Source pin and profile selection

The source audit uses local Genes commit
`6f2e4342f0c9c0b7a68689f9556a2041857d15a9`. That checkout is behind its
remote branch, so this hash is the complete review identity.

The two selected workflows derive from `tests/output-modes`:

| Profile | Existing evaluated command | Important behavior |
| --- | --- | --- |
| Classic | `haxe tests/output-modes/build-classic.hxml` | ESM JavaScript, declarations, source maps, resources, full DCE, transactional publication |
| TypeScript | `haxe tests/output-modes/build-ts.hxml` | Strict TypeScript source, source maps, resources, full DCE, pre-DCE public surfaces and signatures |

These existing workflows are representative baselines. The first native tracer
will be smaller, so a contract failure has one clear cause.

## Required lifecycle

The lifecycle below is part of correctness. The host cannot run every hook
before target emission, as current `Stage3HookSupport` does.

| Order | Event | Owner | Required result |
| ---: | --- | --- | --- |
| 1 | Install `Generator.use()` | Macro host | Validate profile, define activation, include `genes.Register`, and isolate compiler output |
| 2 | Install pre-DCE collectors | Macro host | Reset and register `ModuleDirectivePlan`, `PublicSurface`, and `SignatureCache` when their profiles require them |
| 3 | Type the program | Compiler host | Produce public typed facts and typed expressions |
| 4 | Run `onAfterTyping` | Compiler host | Capture module directives, public API surfaces, and source-level TypeScript signatures |
| 5 | Run DCE and finalize the generation set | Compiler host | Select the exact types and expressions visible to the target |
| 6 | Run `onGenerate` | Compiler host | Stamp the final types once for request-local reachability |
| 7 | Freeze the native request | Compiler host | Encode immutable facts and negotiated services; revoke mutable compiler access |
| 8 | Plan and emit | Native Genes core | Build Genes-owned plans and write only to a private candidate root |
| 9 | Validate and seal | Native Genes core | Return a candidate manifest and opaque request token |
| 10 | Publish | Compiler host | Commit the dedicated output root atomically or preserve the previous tree |
| 11 | Run `onAfterGenerate` | Compiler host | Run exactly once, only after successful publication |
| 12 | Close | Both | Clear callbacks, snapshots, features, handles, candidate paths, and request-local target state |

An error before step 10 must not change public output. An error in step 10 must
roll back the complete output set. No later request may observe state from the
failed request.

## Frozen generator facts

These values belong in the future custom-generator request. They are immutable
target facts, not callable access to a live compiler.

| Genes input | Classification | Required representation | Current `hxhx` status |
| --- | --- | --- | --- |
| `JSGenApi.outputFile` or `genes.output` | Immutable request fact | Normalized requested output identity, profile, and dedicated root | Output hints and server staging exist; Genes ownership is not modeled |
| `JSGenApi.types` | Immutable request fact | Final post-DCE module-type graph with stable declaration identities | `hxhx` has typed modules, but not upstream `haxe.macro.Type` parity |
| `JSGenApi.main` | Immutable request fact | Optional typed main expression with stable local and declaration identities | A main expression exists internally; no custom-generator snapshot exists |
| `BaseType` facts | Immutable request fact | Module, package, name, kind, visibility, extern/private flags, metadata, position, generics, parents, interfaces | Partial facts exist in `TyperIndex`; the full public contract is missing |
| `ClassField` facts | Immutable request fact | Name, type, kind, access, visibility, static/final/abstract flags, metadata, position, expression, overloads, parameters, docs | Partial field and expression facts exist; source API completeness is unproved |
| Enum facts | Immutable request fact | Constructors, indices, parameters, metadata, expressions, and exact enum-abstract identity | Partial native-target facts exist; custom-generator completeness is unproved |
| Typedef and abstract facts | Immutable request fact | Authored alias/backing type, parameters, metadata, source identity, and enum values | Partial facts exist; pre-DCE source spelling is not frozen for a plugin |
| Typed expressions | Immutable request fact | Exhaustive public typed-expression algebra with positions, exact types, locals, and declaration refs | `hxhx` uses its own typed tree; semantic parity for Genes is missing |
| Source positions | Immutable request fact | File identity plus exact `min` and `max`; optional line data is derived | Position facts exist, but no native request schema exists |
| Defines | Immutable request fact | Sorted name/value snapshot fixed before activation | `MacroState` records defines; request freezing and identity are missing |
| Class paths | Immutable request fact | Ordered, normalized source roots with provenance | A macro-facing snapshot exists; immutable plugin transfer is missing |
| Resources | Immutable request fact | Sorted name and byte payload or content digest with bounded read access | Resources reach Stage3 backends; custom-generator transfer is missing |
| Target features | Request-local fact set | Initial features plus deterministic additions made during emission | No native custom-generator feature service exists |

The snapshot must preserve declaration identity. Text names alone cannot safely
distinguish overloads, local variables, same-named fields, abstract helpers, or
module fields.

## Bounded generator actions

The native generator may request these effects. The host validates them and
records them in the final receipt.

| Action | Classification | Boundary rule | Current `hxhx` status |
| --- | --- | --- | --- |
| Emit error, warning, or information | Bounded host action | Typed diagnostic with stable code, severity, message, and source position | Macro messages exist; plugin result integration is missing |
| Query a target feature | Request-local service | Read only from the request feature set | Missing for native custom generators |
| Add a target feature | Bounded host action | Add one validated string to this request only; Genes does not consume the nominal return value | Missing for native custom generators |
| Render a standard JS statement | Provisional bounded service | Either exact upstream-compatible rendering or a fail-closed unsupported result | Missing; never substitute Stage3 JS lowering silently |
| Render a standard JS value | Provisional bounded service | Same rule as statement rendering | Missing; never substitute Stage3 JS lowering silently |
| Install a type accessor | Provisional bounded service | A typed name-resolution policy for this request, not a live closure across the ABI | Missing; the final shape needs a reduced fixture |
| Stage text or bytes | Bounded host action | Write only under the session candidate root | Server output staging exists; plugin-scoped capability is missing |
| Seal candidate output | Bounded host action | Close writers and return sorted paths, digests, roles, and ownership identity | Missing for native custom generators |
| Publish candidate output | Host-only action | The host validates and commits a dedicated root | `CompilationRequestOutputTransaction` provides useful substrate |
| Complete after publication | Bounded post-publication action | Consume a typed publication receipt; run callbacks once | Missing; current hooks run before backend emission |
| Abort and close | Idempotent lifecycle action | Remove private state and files without changing public output | Request cleanup exists; custom-generator token ownership is missing |

`generateStatement`, `generateValue`, and `setTypeAccessor` are provisional.
They must not become generic string callbacks merely because `JSGenApi` uses
functions. The reduced fixtures must show whether a typed intrinsic catalog or
another public fact can replace each callback.

The stock Haxe 4.3.7 fixture observes `null` from `JSGenApi.addFeature`, then
observes the new feature through `hasFeature`. The pinned Genes source already
models `addFeature` as a `Void` action. A native host must preserve the effect
and must not make target behavior depend on that nominal `Bool` return.

## Portable Genes behavior

The following behavior remains in the Haxe-authored Genes core:

- typed module grouping and root selection;
- dependency, binding, name, temporary, module-function, JSX, and nullish plans;
- classic ESM and strict TypeScript syntax decisions;
- declaration generation;
- source-map construction;
- public-surface and signature interpretation;
- import extension and module-directive policy;
- diagnostic choice and wording;
- the candidate file set and its Genes ownership manifest.

The compiler host must not reconstruct these decisions. Native promotion must
execute this same semantic implementation for builtin and plugin forms.

## Filesystem and native access

The Genes source scan found these direct operations:

| Source API | Classification | Native rule |
| --- | --- | --- |
| `File.getBytes`, `getContent` | Bounded read action | Resolve through declared input roots and record the read identity |
| `File.saveBytes`, `saveContent`, `write` | Bounded candidate action | Restrict to the private candidate root |
| `FileSystem.absolutePath`, `fullPath` | Host path service | Normalize relative to the request working directory; do not expose arbitrary host traversal |
| `FileSystem.exists`, `isDirectory`, `readDirectory` | Bounded filesystem query | Restrict to declared input and candidate roots |
| `FileSystem.createDirectory`, `deleteDirectory`, `deleteFile`, `rename` | Bounded candidate or host action | Native code may mutate only its candidate; public rename and rollback stay host-owned |
| `Sys.getCwd` | Immutable request fact | Supply the normalized request working directory |
| `Sys.getEnv` | Native-only access requiring replacement | Replace output-temp lookup with a session-owned candidate root; inventory every other variable before admission |
| `Sys.systemName` | Immutable capability fact | Supply a normalized host-platform value |

Direct OCaml filesystem access is not permission to mutate public output. The
host remains the authority for publication and rollback.

## Public macro API used by the pinned source

This list comes from a repository-wide scan of `genes/src`. It includes the
generator, pre-DCE collectors, and optional source macros.

### Compiler mutations

| API | Role | Current classification |
| --- | --- | --- |
| `Compiler.define` | Activates request-local Genes behavior | Bounded macro-host action; current `hxhx` support exists |
| `Compiler.include` | Forces `genes.Register` into the compilation | Bounded macro-host action; current `hxhx` support is partial |
| `Compiler.addGlobalMetadata` | Installs build/type metadata for Genes helpers | Bounded macro-host action; `hxhx` has a partial ledger, not full semantics |
| `Compiler.getOutput`, `setOutput` | Captures and isolates Haxe's output slot | Macro-host output action; native session must replace the sentinel trick with owned staging |
| `Compiler.setCustomJSGenerator` | Selects Genes as the JS target generator | Missing generic activation contract |

### Lifecycle and diagnostics

| API | Role | Current classification |
| --- | --- | --- |
| `Context.onAfterInitMacros` | Installs behavior after macro initialization | Macro-host lifecycle; exact selected-feature use needs a focused fixture |
| `Context.onAfterTyping` | Captures pre-DCE typed facts | Required lifecycle; callbacks exist but fact payload parity is missing |
| `Context.onGenerate` | Observes final generation types | Required lifecycle; current callback order is too early for publication semantics |
| `Context.onAfterGenerate` | Cleans the output sentinel | Required post-publication lifecycle; current Stage3 order is incorrect |
| `Context.error`, `fatalError`, `warning`, `info` | Emits source-positioned diagnostics | Bounded macro-host action; parity and native result mapping need proof |
| `Context.timer` | Measures named macro phases | Optional diagnostic action; not a correctness fact |

### Compiler facts and typing services

| API group | APIs found | Boundary decision |
| --- | --- | --- |
| Defines and positions | `defined`, `definedValue`, `currentPos`, `getPosInfos`, `makePosition` | Snapshot defines; encode positions as values |
| Type lookup and normalization | `getType`, `getModule`, `follow`, `followWithAbstracts` | Macro host serves lookup during typing; generator receives resolved typed refs |
| Type checking | `resolveType`, `typeExpr`, `typeof`, `unify`, `getExpectedType` | Macro-host services for source macros; never expose a live typer to the generator ABI |
| Local macro context | `getBuildFields`, `getLocalClass`, `getLocalImports`, `getLocalMethod`, `getLocalModule`, `getLocalVars` | Source-macro-only context; exclude from the frozen generator request |
| Source parsing and definition | `parseInlineString`, `defineType` | Source-macro-only actions; exclude from the frozen generator request |
| Search roots | `getClassPath` | Snapshot for source-map and input provenance use |

The scan also found these pure typed-tree helpers:
`TypeTools.applyTypeParameters`, `iter`, `map`, `toComplexType`, and `toString`.
Native Genes must implement them over its typed immutable value model. They are
not host callbacks.

### Exact scanned API symbols

This list prevents a grouped description from hiding an unclassified source
dependency. Each symbol maps to the tables above.

- Compiler actions: `Compiler.addGlobalMetadata`, `Compiler.define`,
  `Compiler.getOutput`, `Compiler.include`, `Compiler.setCustomJSGenerator`,
  and `Compiler.setOutput`.
- Lifecycle and diagnostics: `Context.error`, `Context.fatalError`,
  `Context.info`, `Context.onAfterGenerate`, `Context.onAfterInitMacros`,
  `Context.onAfterTyping`, `Context.onGenerate`, `Context.timer`, and
  `Context.warning`.
- Defines and positions: `Context.currentPos`, `Context.defined`,
  `Context.definedValue`, `Context.getPosInfos`, and `Context.makePosition`.
- Type and module services: `Context.follow`,
  `Context.followWithAbstracts`, `Context.getModule`, `Context.getType`,
  `Context.resolveType`, `Context.typeExpr`, `Context.typeof`, and
  `Context.unify`.
- Local macro context: `Context.getBuildFields`, `Context.getExpectedType`,
  `Context.getLocalClass`, `Context.getLocalImports`,
  `Context.getLocalMethod`, `Context.getLocalModule`, and
  `Context.getLocalVars`.
- Macro parsing and declaration: `Context.defineType` and
  `Context.parseInlineString`.
- Search roots: `Context.getClassPath`.
- Typed-tree helpers: `TypeTools.applyTypeParameters`, `TypeTools.iter`,
  `TypeTools.map`, `TypeTools.toComplexType`, and `TypeTools.toString`.
- File reads and writes: `File.getBytes`, `File.getContent`,
  `File.saveBytes`, `File.saveContent`, and `File.write`.
- Filesystem queries and actions: `FileSystem.absolutePath`,
  `FileSystem.createDirectory`, `FileSystem.deleteDirectory`,
  `FileSystem.deleteFile`, `FileSystem.exists`, `FileSystem.fullPath`,
  `FileSystem.isDirectory`, `FileSystem.readDirectory`, and
  `FileSystem.rename`.
- Process facts: `Sys.getCwd`, `Sys.getEnv`, and `Sys.systemName`.

## Request-local and persistent state

| State owner | State found at the pinned revision | Required isolation |
| --- | --- | --- |
| `Generator` | Persistent generation counter; configured output; private sentinel; output-override snapshot; TypeScript-profile snapshot | Activation resets request values; generation identity advances once; close removes every output handle |
| `Genes` | Persistent output extension | Set from the frozen request and clear on close |
| `ModuleDirectivePlan` | Owners, seen owners, finalized plans | Reset before its `onAfterTyping` callback; immutable after validation |
| `PublicSurface` | Captured classes, interfaces, typedefs, members, overloads, parents, and source types | Reset before capture; never reuse across requests |
| `SignatureCache` | Signatures, field and anonymous-field types, typedefs, locals, enum-abstract spellings | Reset before capture; never reuse across requests |
| JS feature set | Queried and extended during emission | Fresh per request; returned in the result receipt |
| Module and dependency plans | Local maps built during generation | Owned by one native request and dropped on close |
| Output transaction | Candidate paths, manifest identity, prior-output backups, commit state | Candidate-private until host publication; abort and close are idempotent |

Compiler-server tests must cover success, typed failure, raw failure, aborted
publication, profile change, define change, file deletion, and a successful
request after each failure.

## Current `hxhx` map

### Reusable substrate

- `MacroState` records request defines, hook IDs, class paths, include roots,
  resources, diagnostics, and partial global metadata.
- The macro host exposes partial `getType`, `getModule`, `getClassPath`, local
  context, and compiler-effect calls.
- `CompilationRequestContext` owns cancellation, cleanup, source/dependency
  completion, phase timing, and server request isolation.
- `CompilationRequestOutputTransaction` stages output and publishes it after
  successful cleanup.

### Named generic gaps

| Gap ID | Missing generic capability | Why Genes needs it |
| --- | --- | --- |
| `CG-ACTIVATE-01` | Register and select one custom generator without a Genes-specific branch | `Compiler.setCustomJSGenerator` is the actual activation point |
| `CG-LIFECYCLE-01` | Preserve after-typing, final-generation, emission, publication, and after-generate order | Genes captures facts before DCE and cleans up only after publication |
| `CG-TYPED-FACTS-01` | Freeze the complete public typed declaration and expression values used by the admitted tracer | `GenIrProgram` is not Haxe's public typed macro model |
| `CG-PREDCE-01` | Carry immutable pre-DCE public surfaces and signature facts into the final request | TypeScript and declarations must preserve source API facts removed by JS DCE |
| `CG-JS-SERVICE-01` | Define fail-closed statement/value rendering and type-accessor behavior | Genes calls the corresponding `JSGenApi` functions |
| `CG-FEATURES-01` | Request-local target feature query and addition | Both emitters select helpers and globals from feature facts |
| `CG-OUTPUT-01` | Candidate-root write, seal, host publish, typed receipt, and post-publication completion | Genes owns a multi-file tree with maps and declarations |
| `CG-STATE-01` | Close all static and persistent compiler state after success or failure | Warm requests must not depend on request order |
| `CG-PROVENANCE-01` | Record source, target-core, schema, toolchain, loader, capability, and artifact identities | Builtin and plugin must prove one exact Genes semantic core |

The current `reflaxe.ocaml.target-core` is not reusable proof for these gaps.
It consumes `GenIrProgram` and delegates to Stage3 `EmitterStage`.

## Reduced generic fixtures

These framework-neutral fixtures must not import or name Genes.

The first stock-Haxe fixture now lives in
`test/fixtures/native_custom_generator_contract`. It proves the real
`onAfterTyping` → `onGenerate` → generator → `onAfterGenerate` order. It also
records pre-DCE declaration kinds and calls the statement, value, type-accessor,
and feature services used by Genes.

The fixture is part of the root test command through
`test:m22:custom-generator-contract`. It does not yet exercise candidate
publication faults or a warm compiler server.

### Fixture A: lifecycle and publication

A small custom generator registers all three lifecycle callbacks. It receives
one class, one enum, one resource, and a main expression.

The fixture writes two candidate files and records this event sequence:

```text
after-typing
on-generate
generator-prepare
host-publish
after-generate
close
```

A fault before seal and a fault during publication must preserve the prior
public tree. A second request in the same server must match a clean process.

### Fixture B: immutable pre-DCE source facts

A public generic interface, implementing class, overload, typedef, and enum
abstract are captured before DCE. The final generation set intentionally drops
one runtime member.

The custom generator must still receive the public signature, authored alias,
overload, generic owner, enum-abstract identity, and exact source position. It
must not receive a mutable `ClassType`, `ClassField`, or host-private object.

### Fixture C: JS service admission

One expression requires statement rendering, one requires value rendering,
and one type name uses the installed accessor.

The builtin tracer must either return the expected public-Haxe result or reject
the request before target execution with `CG-JS-SERVICE-01`. Placeholder text
or Stage3-specific rendering is a failure.

## Native tracer bullets

### Classic JavaScript tracer

Input: one main class, one imported module, one exposed public type, one
resource, and one stale file from a previous successful build.

Required result:

- classic ESM JavaScript plus `.d.ts` and source maps;
- target checking and execution under Node;
- the expected runtime trace;
- a deterministic sorted candidate manifest;
- removal of only the stale Genes-owned file;
- preservation of an adjacent user-owned file;
- exact builtin/plugin semantic identities after both forms exist;
- fail-closed behavior if Fixture C needs an unsupported JS service.

### TypeScript tracer

Input: the classic graph plus a generic public interface, overload, typedef,
enum abstract, optional field, and a typed local that refers to the alias.

Required result:

- strict TypeScript and source maps;
- `PublicSurface` and `SignatureCache` facts captured before DCE;
- public generics, overloads, alias spelling, optionality, and enum literal
  union preserved;
- strict `tsc` success followed by the expected Node trace;
- byte-equivalent warm and cold trees at the pinned stable compiler;
- the same rollback, state isolation, provenance, and builtin/plugin identity
  checks as the classic tracer.

## Evaluated baseline

The baseline must measure the selected evaluated commands before a native
comparison. Each sample must report:

1. compiler startup and plugin installation;
2. parse, type, and DCE;
3. pre-DCE capture;
4. Genes planning and emission;
5. candidate publication;
6. TypeScript or JavaScript checking;
7. runtime execution;
8. complete loop time and peak memory.

The existing Genes command reports only whole-build time. The current
`Context.timer` calls and the Genes output-quality runner provide partial phase
evidence, but they do not yet satisfy this baseline.

A separate exploratory compile of the full `hxhx.Main` through evaluated Genes
TypeScript remained CPU-active after 39 minutes and had produced no files. It
ran concurrently with other work, so it is bottleneck evidence only. It is not
a valid performance sample and must not be used for a speedup percentage.

The next baseline run must use a quiet host, background scheduling, pinned
toolchains, a warmup, repeated samples, and one same-run control. Exact blocking
thresholds remain report-only until variance is known.

## Exit criteria for this inventory task

This document completes the source classification and tracer definitions. The
task remains open until the existing fixture covers the fault and warm-server
cases, its pre-DCE assertions cover the complete admitted fact slice, and the
evaluated classic and TypeScript baselines contain phase-separated samples.

Those additions may refine the experimental request fields. They may not widen
the request to private mutable compiler objects or freeze a public ABI.
