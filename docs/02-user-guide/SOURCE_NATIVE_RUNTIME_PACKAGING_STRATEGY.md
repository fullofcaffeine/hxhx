# Source-Native Runtime Packaging Strategy

Status: accepted direction for Full1 burn-down; implementation is incremental.

Owning bead: `haxe.ocaml-5am1`.

Last updated: 2026-06-15.

## Purpose

The source-native backends currently emit some target runtime support directly from
`SourceTargetCommon.hx` with large `lines.push` / `out.push` blocks. That was a
pragmatic way to unblock early target gates, but it makes runtime behavior hard
to review, hard to test in isolation, and too easy to grow target libraries
inside a compiler emitter.

This document defines the boundary we should use going forward: what can remain
compiler-owned generated glue, what should move to repo-owned runtime templates
or typed support modules, and what belongs behind extern/intrinsic APIs such as
PHP native syntax helpers.

## Decision Summary

Use templates or typed runtime-support modules for stable target runtime code.
Keep compiler-owned emitters only for program-shaped glue that depends on the
current compilation unit.

Recommended near-term path:

1. Extract stable runtime bodies from `SourceTargetCommon.hx` into small,
   repo-owned files under `packages/hxhx-core/source-templates/<target>/`.
2. Keep generated maps, metadata tables, class registries, entrypoint wrappers,
   and per-program bindings in emitters, but make those emitters table builders,
   not miniature target standard libraries.
3. Model target-native syntax escape hatches as extern/core APIs plus direct
   intrinsic lowering. Do not fake them by generating broad runtime classes.
4. Use checked-in generated assets only when the asset is a deliberate bootstrap
   snapshot or release artifact. Do not create opaque generated runtimes when a
   readable template would do.

This intentionally diverges from older monolithic compiler-file patterns where a
cleaner, MIT-owned architecture is available. We should still match upstream Haxe
at the observable behavior level for Haxe 4.3.7 compatibility claims.

## Boundary Rules

| Surface | Classification | Direction |
| --- | --- | --- |
| Class-name maps, metadata maps, reflection visibility tables, resource tables | Compiler-owned generated glue | Keep generated, but emit as compact data/table builders. |
| `__hxhx_*` helpers with stable target behavior | Runtime support | Move to target templates or typed runtime modules. |
| Haxe stdlib facades such as `Type`, `Reflect`, `Std`, `Sys`, `Math`, `Xml`, `StringBuf`, `Date`, `haxe.io.Bytes` | Runtime support or target stdlib surface | Prefer templates/modules, with focused smoke coverage. |
| Entrypoint wrappers and main-body lowering | Compiler-owned generated glue | Keep in emitter, because it is per-program shape. |
| Test-only harness shims such as utest runner adapters | Test harness support | Keep small; prefer templates if repeated or target-language-sized. |
| Target-native syntax helpers such as `php.Syntax` / `__php__`-style APIs | Extern/intrinsic boundary | Prefer extern/core declarations plus direct intrinsic lowering. |
| Fake generated classes added only to satisfy one gate | Anti-pattern | File an architecture bead before expanding; extract or redesign. |

## Current Inventory

| Target | Current surfaces | Classification | Direction |
| --- | --- | --- | --- |
| PHP | `renderPhpSupportClasses`, `appendPhpGenericStackRuntime`, `appendPhpXmlRuntime`, `appendPhpDateRuntime`, `appendPhpDateToolsSupport`, `appendPhpStringBufRuntime`, `appendPhpResourceRuntime`, reflection/meta helpers, class-name maps | Mixed: large stable runtime plus generated program tables | Highest priority. Split stable runtime into PHP templates and keep generated maps/resources as injected tables. |
| PHP native syntax | `php.Syntax` / raw PHP expression seams | Extern/intrinsic boundary | Define policy and lower narrow syntax forms directly. Do not grow PHP runtime classes for compile-time syntax. |
| C# | `renderCsRuntimeSupportSource`, import-stub members, `appendCsUtilityProcessRuntime`, `appendCsUtestRunnerAddCasesStub`, `appendCsPostUpdateVarSupport`; some import stubs already templated | Mixed runtime templates, harness shims, small glue | Continue extraction. Stable support should live in C# templates; small expression-lowering helpers may remain generated. |
| Java | Import-stub members, nested stubs, array/std support, signal support, main support, utility-process runtime | Mixed runtime and generated class shape | Template stable Java support. Keep class-shape/nested-stub emission generated where it depends on the imported type. |
| Python | `appendPythonReflectSupport`, `appendPythonTypeSupport`, `appendPythonStringToolsSupport`, `appendPythonVectorSupport`, `appendPythonMetaSupport`, `appendPythonDateToolsSupport`, `appendPythonStringMapSupport`, test/macro helper shims | Mostly stable runtime shims plus a few test helpers | Move stable std/runtime shims to Python templates. Keep target gate-only helpers small and documented. |
| Lua | `renderLuaSupportPrelude`, `appendLuaERegRuntime`, support-class bindings, utility-process runtime, main static helpers | Large runtime prelude plus generated package bindings | Extract runtime prelude/EReg support to templates. Keep package/class bindings generated. |

## Options Compared

### Option A: Inline emitters with extracted templates/modules

This is the recommended path. The compiler still owns when to include support,
but target-language bodies live in small readable files or typed helper modules.

Pros:

- Keeps bootstrap behavior simple: committed templates are repo-owned source.
- Makes diffs reviewable in the target language.
- Avoids large generated artifacts.
- Allows focused smoke tests to assert template inclusion.
- Works with current source-native output model.

Cons:

- Requires gradual extraction and template-loading discipline.
- Still needs clear ownership so templates do not become a second monolith.

### Option B: Checked-in generated/runtime assets

This means producing larger target runtime files from a generator and committing
those outputs.

Pros:

- Can be useful for deliberate bootstrap snapshots or release bundles.
- Avoids runtime file discovery if assets are fully baked into generated output.

Cons:

- Opaque diffs are harder to review.
- Easy to create large artifacts and cache churn.
- Bad fit for hand-authored target runtime behavior unless the generator has a
  strong reason to exist.

Use this sparingly. Bootstrap snapshots are the known legitimate case; normal
source-native runtime support should prefer readable templates.

### Option C: Extern/native-snippet APIs

This models target-native behavior through Haxe-facing APIs and direct intrinsic
lowering, for example PHP syntax escape hatches.

Pros:

- Good fit for compile-time syntax and narrow FFI/native escapes.
- Keeps user-facing APIs typed and discoverable.
- Avoids pretending target syntax is a runtime class.

Cons:

- Not a replacement for broad Haxe stdlib/runtime support.
- Requires careful lowering rules and regression coverage.
- Can become an unsafe escape hatch if allowed to spread without policy.

Use this for native syntax and intentionally exposed target intrinsics, not for
`Type`, `Reflect`, `Array`, `Date`, or other general runtime surfaces.

## Constraints

Stage0-free builds:

- Templates must be repo-owned and available to the native `hxhx` binary without
  invoking upstream Haxe.
- If a template affects generated bootstrap output, regenerate bootstrap snapshots
  through repo scripts and keep the diff reviewable.

Bootstrap snapshots:

- `packages/hxhx/bootstrap_out/` and
  `packages/hxhx-macro-host/bootstrap_out/` remain generated artifacts.
- Do not hand-edit snapshots to patch runtime behavior.

Artifact size and disk hygiene:

- Prefer small source templates over large generated runtime outputs.
- Heavy target/bootstrap runs must continue to use the repo cleanup workflow.
- Do not retain temporary generated target trees as evidence when a gate log or
  focused test assertion is enough.

CI cache shape:

- Template changes should have focused smoke coverage for the affected target.
- Broader upstream gates remain release evidence, but not every template edit
  should require a full local target matrix before commit.

Provenance and licensing:

- Runtime templates must be written from scratch unless explicitly handled under
  the stdlib reuse policy.
- Upstream Haxe compiler and test sources remain oracle-only; do not copy or
  mechanically rewrite them.
- Architecture can be inspired by upstream concepts, but implementation must be
  repo-owned and behavior-driven.

Target-backend coupling:

- Keep target-specific runtime files under target-specific template directories.
- Common dispatch may decide which support file to include, but target runtime
  bodies should not live in common emitter code.

Upstream compatibility:

- Stay close to upstream Haxe for observable semantics and public compatibility
  claims.
- Diverge in internal packaging where it improves maintainability, reviewability,
  MIT provenance, or testability.

## Migration Plan

1. PHP stable runtime template split.
   - Priority: P2.
   - Bead: `haxe.ocaml-yt1u`.
   - Move stable PHP runtime classes/helpers from `renderPhpSupportClasses` and
     adjacent `appendPhp*Runtime` functions into template families such as
     runtime core, std/type/reflection, XML/date/string/resource support, and IO
     support.
   - Keep generated class-name, reflection, metadata, and resource maps emitted
     as data injected around those templates.

2. PHP generated registry/table cleanup.
   - Priority: P2.
   - Bead: `haxe.ocaml-bwq4`.
   - After stable runtime extraction, reduce generated PHP registry emitters to
     compact table builders with named insertion points.

3. C# remaining support extraction.
   - Priority: P3.
   - Bead: `haxe.ocaml-1awf`.
   - Continue the existing C# template direction for import-stub members and move
     repeated utest/utility-process/runtime support out of inline `out.push`
     blocks when it becomes target-language-sized.

4. Lua runtime prelude extraction.
   - Priority: P3.
   - Bead: `haxe.ocaml-st8x`.
   - Move stable Lua prelude and EReg helpers to templates; keep per-program
     package/class binding generation in the emitter.

5. Java support extraction.
   - Priority: P3.
   - Bead: `haxe.ocaml-1nu4`.
   - Template stable std/array/signal/utility-process support. Keep generated
     class/interface/enum-like shapes in the emitter because they depend on Haxe
     declarations.

6. Python support extraction.
   - Priority: P3.
   - Bead: `haxe.ocaml-mmnm`.
   - Template stable Reflect/Type/StringTools/Vector/Meta/DateTools/StringMap
     support. Keep test-only shims small, documented, and covered.

7. Target-native intrinsic/extern policy.
   - Priority: P3, thinking:high.
   - Bead: `haxe.ocaml-ajze`.
   - Define when APIs such as `php.Syntax` are extern/core declarations with
     direct lowering versus runtime support. Apply the rule to adjacent raw
     target APIs as they appear.

## Checkpoint Review

README Goals status reviewed for this R&D checkpoint: no table update is
required. The production usability of the main public goals did not change; this
checkpoint records architecture direction and follow-up implementation work.
