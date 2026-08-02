# OCaml Metal Source-Boundary Decision

**Bead:** `haxe_ocaml-5q9hz`

**Local candidate:** `ed591b649e12e6c8ce54556446fbfcc0290ca41b`

**Decision date:** 2026-08-02

**Status:** accepted architecture decision; implementation and verification are tracked by the Bead

## Decision

Remove `@:haxeMetal` from the OCaml source contract. Do not replace it with
another annotation now.

Portable Haxe, explicit OCaml APIs, and generated-code optimization are three
different choices:

1. **Portable Haxe semantics** describe how ordinary Haxe source must behave.
2. **OCaml-native source** explicitly uses typed `ocaml.*` APIs or typed externs
   when the program intentionally depends on OCaml behavior.
3. **Direct lowering** is a compiler optimization: the compiler emits a simple,
   statically typed OCaml representation whenever it can prove that doing so
   preserves the selected source behavior.

For example, an ordinary `Array<Int>` can use an efficient typed OCaml carrier
without an annotation. Importing `ocaml.List<Int>` is an explicit OCaml-only API
choice. Neither case needs a marker that says “metal.”

The build-wide `-D ocaml_profile=metal` input remains for now. It currently
bundles strict boundary checks, fail-closed fallback policy, and selective
runtime packaging. This decision does not remove or silently redefine that
bundle. It clarifies that the bundle is not required for good OCaml output and
does not authorize a second semantic compiler.

## What `@:haxeMetal` actually did

The annotation was introduced in February 2026 as a family-alignment feature.
In the current standalone target it only made one generated Haxe module reject:

- explicit `Dynamic` declarations;
- `Reflect.*` and `Type.*` calls; and
- raw `__ocaml__` injection.

It did not:

- select a faster representation;
- enable the portable direct-lowering planner;
- grant access to `ocaml.*` APIs;
- select runtime modules;
- change an OCaml function's calling convention; or
- provide an FFI ownership or lifetime guarantee.

The repository has no application, package, or example using the annotation.
Its only source use outside the analyzer and test harness is the negative test
fixture that proves the restriction fires.

Calling this a “metal island” therefore suggests a behavior it does not own.
It also creates a generic cross-target source label for a target-specific
policy. A developer could reasonably add the annotation to make a hot function
faster even though the annotation has no such effect.

## Sibling-target evidence

The historical OCaml alignment spike explicitly requested a fresh comparison
after the sibling compilers stabilized. The comparison below uses the named Git
commits. The relevant files were unchanged in each inspected working tree; the
Go and Rust repositories contained unrelated local changes, so this decision
does not treat their entire working trees as immutable evidence.

| Target | Inspected identity | Current model | Consequence for OCaml |
| --- | --- | --- | --- |
| Go | `9bc7c6f346212315d10e17a16f18988bcb54e005` | Portable behavior is the default. Proven Go-shaped lowering is automatic. `@:goNative` names real Go-specific source authority; `@:haxeMetal` is rejected. The global metal input is a compatibility policy preset. | Strong match: use typed `ocaml.*` surfaces for native intent and keep optimization compiler-owned. |
| Rust | `dd19f60315fc38d14c5ea0b5e9e1962f480aa1f6` | `@:rustMetal` remains because Rust ownership, nullability, borrowing, RAII, async, and no-runtime eligibility form a real Rust-specific source contract. | This is a justified target-specific exception, not a family-wide annotation requirement. OCaml has no corresponding local contract today. |
| Ruby | `dbb70af0e48e252e413645b7bf16197a4776f0f8` | Ruby has portable and Ruby-first authoring profiles but deliberately no metal profile or metal annotation. Performance policy is orthogonal. | A dynamic target can mix portable and native APIs without inventing a performance island. |
| Elixir | `a3f3ff127fae91f19db562e6f4d7e0fe7799f188` | Source APIs communicate portable versus BEAM-native intent. Strictness is an independent flag. “Metal” is reserved for a raw-template escape hatch, not application compilation. | Strong match: native API choice and safety checks should not masquerade as a lowering mode. |

Primary sibling references:

- `../haxe.go/docs/profiles.md`
- `../haxe.go/docs/native-policy-presets.md`
- `../haxe.go/docs/metal-preset-retention-decision.md`
- `../haxe.rust/docs/profiles.md`
- `../haxe.rust/docs/portable-vs-metal-authoring.md`
- `../haxe.ruby/docs/profiles.md`
- `../haxe.elixir.codex/docs/05-architecture/AUTHORING_PROFILE_CONTRACT.md`

## Why OCaml does not require a local metal island

OCaml has target-specific representation questions—boxed versus unboxed
values, runtime helper ownership, native modules, functors, and FFI adapters—but
none requires a module-wide “metal” bit.

- A portable operation receives a direct carrier only after its Haxe behavior,
  evaluation order, mutation, identity, nullability, calls, control effects,
  and runtime needs are proven.
- An OCaml-native API declares its own typed target contract at the imported
  surface or extern boundary.
- Runtime modules are selected from sealed compiler requirements and checked
  source manifests, not from a source annotation.
- Unsupported direct lowering must remain a semantics-safe portable path or a
  fail-closed diagnostic. An annotation must not turn an unproved lowering into
  an accepted one.

A future local assertion may still be useful, but it must earn a precise name
and a real consumer. For example, `@:ocamlStrict` could one day mean “reject
specific compatibility fallbacks in this module,” while `@:ocamlNative` could
one day declare module-wide native API authority. Neither contract exists or is
needed today, so adding either now would be speculative.

## Resulting user model

### Portable code that should stay portable

Write ordinary Haxe. The compiler should emit direct typed OCaml whenever that
is safe and use the smallest compatibility support needed when it is not.

### A portable project with an OCaml-specific edge

Use a typed `ocaml.*` API or typed extern in the owning boundary module. The
existing `ocaml_portable_native_surface=warn|allow|error` policy controls
whether that intentional target dependency is reported, accepted, or rejected.
No metal annotation is required.

### A build that must reject compatibility-heavy constructs

Use the current build-wide metal preset or explicit strict/runtime controls.
This remains a whole-build policy until a separate reviewed change decomposes
the preset into independently named axes.

## Hard-cut behavior

The annotation was never part of a released product and has no repository
consumer. The hard cut therefore removes its analyzer, fixtures, and report
fields without a compatibility alias or migration guard. New documentation
teaches the three actual controls—portable semantics, typed `ocaml.*` APIs, and
build-wide strict/runtime policy—rather than preserving code for an unpublished
name.

The profile report should no longer claim module-level lane ownership. Its
schema must change if lane fields are removed.

## Global metal follow-up

The global preset is less cleanly separated than Go's current implementation.
The legacy Stage3 emitter still branches directly on the profile for several
lowerings, while the authentic standalone target mainly uses the profile for
strictness and runtime packaging. Stage3 is already excluded from authentic
shared-target readiness and is scheduled for the hard cut.

Do not redesign the global preset around Stage3. Reassess it after the
standalone target is the only semantic OCaml implementation. That review should
decide whether `metal` remains a convenient preset over explicit strictness,
native-authority, fallback, runtime, and optimization policies.

## Oracle disposition

A deep Oracle review is not required to remove the local annotation. The local
implementation, repository usage inventory, and four sibling models all agree:
the annotation owns no OCaml-specific source semantics or optimization.

A focused Oracle review is appropriate before a future global-profile hard cut
if the authentic standalone target still needs profile-dependent
representation or calling behavior after Stage3 is removed. That broader
question affects runtime compatibility and performance evidence and is outside
this decision.

## Second-pass architecture review

The required independent second pass challenged four plausible alternatives:

1. **Keep `@:haxeMetal` as a local assertion.** Rejected because it asserts no
   representation, calling, ownership, runtime, or FFI contract. Global
   `ocaml_strict` already provides the only behavior the annotation supplied.
2. **Rename it to an OCaml-specific annotation.** Rejected because a new name
   would still lack a distinct semantic consumer. Typed `ocaml.*` APIs already
   identify intentional target-native source without controlling optimization.
3. **Keep a removal guard for old source.** Rejected because the annotation was
   never released and has no real repository consumer. A guard would preserve
   an abandoned concept solely to diagnose its removal.
4. **Delete the global metal preset in the same change.** Rejected because the
   preset still owns real whole-build strictness, fallback, and runtime-package
   policy. Its reassessment is now tracked by `haxe_ocaml-f9n53`, blocked on the
   authentic target-core hard cut `haxe_ocaml-38gsp.1`.

The generated-source snapshot comparison changed only profile reports: every
OCaml source file remained identical. Focused strictness, runtime, inspection,
profile, numeric, automatic direct-lowering, and array/string specialization
tests also passed. This evidence is sufficient for the local hard cut, so an
Oracle review would add process without resolving an open local question.

## Verification contract

The implementation must prove:

1. the former source-local analyzer and fixtures are absent;
2. portable native-surface warn, allow, and error policies still work;
3. global metal strict violations still fail, and explicit fallback still
   reports warnings;
4. portable direct-lowering and global metal lowering fixtures remain green;
5. profile/runtime reports use their revised schema consistently; and
6. formatting and documentation guards pass.
