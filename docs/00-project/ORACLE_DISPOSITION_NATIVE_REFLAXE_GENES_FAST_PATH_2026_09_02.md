# Oracle disposition: native Reflaxe and Genes fast path

Date: 2026-09-02

Oracle request: `orq_20260902T181832Z_0d08793e`

Recorded work owner: `haxe-ocaml-native-target-owner`

Active task: `haxe_ocaml-bomhr.2.1`

## Outcome

Proceed with a private native compiler-session experiment, but do not call the
current Stage3 backend native Reflaxe. The first durable step is still the
authentic shared-target cut in `haxe_ocaml-38gsp.1`.

Inventory work for Genes can continue now. Its implementation remains gated by
the authentic shared target, native self-promotion, and the existing release
rules.

## Local baseline before review

The local plan already required these steps:

1. Make upstream Haxe and native `hxhx` execute the same standalone
   `reflaxe.ocaml` target implementation.
2. Compile that target through itself and execute the native artifact without
   stage0 delegation.
3. Use Genes as the first custom-generator consumer.
4. Keep cross-target `hxhx` builds as a secondary portability proof. Native
   OCaml remains the main compiler distribution.

The Oracle response did not replace this order. It made the target boundary,
publication lifecycle, and experimental claim limits more precise.

## Evidence checked locally

The response was compared with source at `9d9f534d4`. The Oracle bundle used
`e01fb06ae`; the intervening committed change only updated roadmap records.

The following source facts support the response:

- `backend.ocaml.OcamlTargetCore` currently calls
  `EmitterStage.emitToDir`. Its input is `GenIrProgram`, which is an alias for
  `MacroExpandedProgram`.
- Standalone `reflaxe.ocaml` creates `OcamlCompiler` in
  `CompilerInit.Start()`. That setup also selects preprocessors, lifecycle
  policy, output shape, and target options.
- Genes installs through `Compiler.setCustomJSGenerator`. It also uses
  `onAfterTyping`, `onGenerate`, and `onAfterGenerate` behavior.
- Genes captures TypeScript and declaration facts before runtime-oriented dead
  code elimination.
- Genes redirects the compiler-owned output to a private sentinel. Its own
  `OutputTransaction` stages, validates, publishes, and rolls back the public
  generated tree.
- `hxhx` already has request cleanup, cancellation checkpoints, and server
  output staging. These are useful substrate, but they do not yet implement
  the Genes generator lifecycle.

No open pull request owns this task. The task remains assigned to the recorded
repository agent. Unrelated JavaScript-emitter edits in the working tree were
not used or changed by this review.

## Retained advice

### One authentic target definition

Extract the actual standalone target definition from `CompilerInit.Start()`.
Upstream activation, a native plugin, and a linked builtin must use that one
definition.

The definition must retain the real `OcamlCompiler`, preprocessors, lifecycle,
runtime selection, output policy, and printer. The current Stage3 emitter is a
comparison lane only.

### Public facts, not private compiler objects

The native target request must be an immutable snapshot of public Haxe compiler
facts. It must not contain `GenIrProgram`, private mutable host objects,
`Dynamic`, or an unexplained `Obj.t` boundary.

Host-specific adapters may normalize facts. They may not choose target
semantics, repair generated source, or reconstruct missing compiler meaning.

### Builtin tracer before loadable plugin proof

Use an internal linked builtin for the first lifecycle tracer. Add the `.cmxs`
loader proof only after the request contract works.

A developer preview requires both forms. The builtin alone is an internal
experiment, not a supported plugin preview.

### Separate request families

Ordinary Reflaxe targets and Genes custom generators need different request
families. They can share session, loader, provenance, cancellation, isolation,
diagnostic, and publication services.

Do not widen the existing Stage3 provider manifest to cover both meanings. Add
an explicitly experimental native compiler-plugin kind.

### Genes lifecycle order

The Genes request must preserve this order:

1. Activate the generator and capture required pre-typing facts.
2. Type the program.
3. Run `onAfterTyping` capture.
4. Select the final generation set after dead code elimination.
5. Run `onGenerate` exactly once.
6. Freeze the immutable native request.
7. Run the native Genes generator into private output.
8. Validate and seal the candidate.
9. Let the host commit the dedicated output root.
10. Run `onAfterGenerate` exactly once after successful publication.
11. Clear all request-local state.

Failure before publication must leave the previous public output unchanged.
Failure must also prevent post-publication callbacks from reporting success.

### Narrow native platform slice

The first native target proof needs a small, typed OCaml platform surface.
That does not make the broad future interop program a prerequisite.

Every native-only operation must have exact Haxe and OCaml types, source
ownership, capability negotiation, validation, and a stable failure mode.

### Claim discipline

The following claims remain separate:

- An internal linked lifecycle tracer proves only the private session model.
- A loadable artifact proves activation and provenance only after it executes
  the same target definition.
- A native Reflaxe developer preview requires the authentic target, stage0-free
  execution, semantic evidence, and representative performance evidence.
- A supported SDK and Full 1.0 compatibility claim still require their
  existing gates.

## Adapted advice

### Two-step publication API

Retain the two-step model, but do not freeze the wire names from this planning
review. The required behavior is:

1. Native code prepares a sealed candidate and returns an opaque request token.
2. The host publishes the candidate and returns a typed receipt.
3. Native code consumes that receipt and completes post-publication behavior.
4. Abort and close remain explicit and idempotent.

The inventory and reduced fixtures must determine the smallest encoded fields.
Only then can a versioned experimental ABI be named.

### Hybrid recorder and replayer

A capture-and-replay experiment is acceptable only as a bounded schema probe.
It must never be named native Reflaxe or native Genes.

If used, it gets at most two schema revisions. It must record its removal gate
before product code depends on it. Calendar estimates from the response are not
used because this repository does not have the assumed staffing model.

### Performance gates

Retain phase-separated measurement and meaningful speedup requirements. Defer
the exact percentages until current workloads and variance are measured.

Measurements must separate at least:

- parsing, typing, and dead code elimination;
- request adaptation;
- plugin load;
- target planning and emission;
- publication;
- downstream target checking or building;
- complete cold and warm loops;
- peak and retained memory.

Native execution, compiler-server reuse, exact-source replay, filesystem cache,
and downstream build cache must be reported separately.

## Deferred decisions

These choices need evidence from the current inventory or a repository-owner
decision:

- the first supported host and platform matrix;
- whether an exact, trusted generation-zero artifact can be distributed;
- the final encoded request and receipt fields;
- the representative large real-world benchmark workload;
- the exact performance thresholds;
- the duration of any hybrid experiment in calendar time.

The current macOS development host is valid for an internal tracer. This review
does not impose a Linux-only product boundary.

## Rejected advice as repository authority

The response's week estimates assume several dedicated senior engineers. They
are useful scale signals, not repository schedules or delivery promises.

Its proposed numeric speedup thresholds are also not adopted as policy yet.
They remain candidate starting points until the baseline task records real
workload distributions.

An identical byte encoding between upstream Haxe and `hxhx` is not required
when the hosts expose justified differences. The durable contract is equivalent
normalized facts, target decisions, behavior, diagnostics, and output identity,
with every host-shell difference retained and explained.

## Integrated next work

`haxe_ocaml-bomhr.2.1` now owns the immediate work:

1. Pin the inspected Genes revision.
2. Inventory every fact, callback, action, and request-local state boundary.
3. Map each item to current `hxhx` support or a named generic gap.
4. Define a fail-closed classic JavaScript tracer.
5. Define a TypeScript tracer that includes public-surface and signature
   capture.
6. Add reduced, framework-neutral fixtures for the missing generic contracts.
7. Record phase-separated evaluated baselines before any native comparison.

This disposition changes no readiness label. It authorizes no Genes-specific
compiler branch and no public ABI freeze.
